-- =====================================================================
-- BLOK 2 / "data_quality_issues" 
-- Output mapping out.c-audit.data_quality_issues (full load).
-- =====================================================================

CREATE OR REPLACE TABLE "data_quality_issues" AS
WITH
------ 1) retype 
orders_prep AS ( 
		SELECT
				NULLIF(TRIM(o."order_id"), '')   AS "order_id",
				NULLIF(TRIM(o."user_id"), '')    AS "user_id",
				NULLIF(TRIM(o."product_id"), '') AS "product_id",
				NULLIF(TRIM(o."order_date"), '') AS "order_date",
				NULLIF(TRIM(o."status"), '')     AS "status",

				LOWER(NULLIF(TRIM(o."status"), ''))           AS status_norm,

				TRY_CAST(NULLIF(TRIM(o."quantity"), '')     AS NUMBER)       AS quantity_n,
				TRY_CAST(NULLIF(TRIM(o."revenue_czk"), '')  AS NUMBER(18,2)) AS revenue_n,
				TRY_CAST(NULLIF(TRIM(o."discount_pct"), '') AS NUMBER(10,4)) AS discount_n,

				rs.status AS status_in_catalog
		FROM "orders" o
		LEFT JOIN "ref_allowed_status" rs
		ON rs.status = LOWER(NULLIF(TRIM(o."status"), ''))
		),
products_prep AS ( 
		SELECT
				NULLIF(TRIM("product_id"), '')   AS "product_id",
				NULLIF(TRIM("product_name"), '') AS "product_name",
				NULLIF(TRIM("category"), '')     AS "category",

				TRY_CAST(NULLIF(TRIM(CAST("price_czk"  AS VARCHAR)), '') AS NUMBER(18,2)) AS price_n,
      	TRY_CAST(NULLIF(TRIM(CAST("margin_pct" AS VARCHAR)), '') AS NUMBER(10,4)) AS margin_n
		FROM "products"
		),
users_prep AS ( 
		SELECT
				NULLIF(TRIM(u."user_id"), '')             AS "user_id",
				NULLIF(TRIM(u."country"), '')             AS "country",
				NULLIF(TRIM(u."acquisition_channel"), '') AS "acquisition_channel",
				NULLIF(TRIM(u."registered_at"), '')       AS "registered_at",
				NULLIF(TRIM(u."age_group"), '')           AS "age_group",
				rag.age_group                             AS age_group_in_catalog
		FROM "users" u
		LEFT JOIN "ref_allowed_age_group" rag
		ON rag.age_group = TRIM(u."age_group")
		),

------ 2) duplicities
dup_orders AS (
    SELECT COALESCE(SUM(cnt), 0) AS dup_rows
    FROM (
        SELECT COUNT(*) AS cnt
        FROM orders_prep
        WHERE "order_id" IS NOT NULL
        GROUP BY "order_id"
        HAVING COUNT(*) > 1
    )
),
dup_products AS (
    SELECT COALESCE(SUM(cnt), 0) AS dup_rows
    FROM (
        SELECT COUNT(*) AS cnt
        FROM products_prep
        WHERE "product_id" IS NOT NULL
        GROUP BY "product_id"
        HAVING COUNT(*) > 1
    )
),
dup_users AS (
    SELECT COALESCE(SUM(cnt), 0) AS dup_rows
    FROM (
        SELECT COUNT(*) AS cnt
        FROM users_prep
        WHERE "user_id" IS NOT NULL
        GROUP BY "user_id"
        HAVING COUNT(*) > 1
    )
),

------ 3) orders
orders_profile AS (
    SELECT
        COUNT_IF("order_id"   IS NULL)                                                  AS null_in_key_order_id,
        COUNT_IF("user_id"    IS NULL)                                                  AS null_in_key_user_id,
        COUNT_IF("product_id" IS NULL)                                                  AS null_in_key_product_id,
        COUNT_IF("order_date" IS NULL)                                                  AS null_order_date,
        COUNT_IF("status"     IS NULL)                                                  AS null_status,

        COUNT_IF("status" IS NOT NULL
                 AND status_in_catalog IS NULL
                 AND status_norm <> 'kompletní')                                        AS invalid_status,

        COUNT_IF(
            ("status" IS NOT NULL AND "status" <> status_norm)
            OR status_norm = 'kompletní'
        )                                                                               AS status_inconsistency,

        COUNT_IF(status_norm IN ('completed', 'kompletní') AND (revenue_n IS NULL OR revenue_n = 0)) AS completed_zero_or_null_revenue,
        COUNT_IF(quantity_n IS NOT NULL AND quantity_n <= 0)                            AS quantity_le_zero,
        COUNT_IF(discount_n IS NOT NULL AND (discount_n < 0 OR discount_n > 1))         AS discount_out_of_range
    FROM orders_prep
),

------ 4)  orders → users / orders → products ----------
orders_fk AS (
    SELECT
        (SELECT COUNT(*)
           FROM orders_prep o
          WHERE o."user_id" IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM users_prep u WHERE u."user_id" = o."user_id"
            )
        ) AS fk_user_id_not_in_users,
        (SELECT COUNT(*)
           FROM orders_prep o
          WHERE o."product_id" IS NOT NULL
            AND NOT EXISTS (
                SELECT 1 FROM products_prep p WHERE p."product_id" = o."product_id"
            )
        ) AS fk_product_id_not_in_products
),

------ 5) products  -----------------------
products_profile AS (
    SELECT
        COUNT_IF("product_id" IS NULL)                                              AS null_in_key_product_id,
        COUNT_IF(price_n IS NULL OR price_n <= 0)                                   AS price_le_zero,
        COUNT_IF("product_name" IS NULL OR TRIM("product_name") = '')               AS missing_product_name,
        COUNT_IF("category"     IS NULL OR TRIM("category")     = '')               AS missing_category,
        COUNT_IF(margin_n IS NOT NULL AND (margin_n < 0 OR margin_n > 1))           AS margin_out_of_range
    FROM products_prep
),

------ 6) users --------------------------
users_profile AS (
    SELECT
        COUNT_IF("user_id"             IS NULL)                                     AS null_in_key_user_id,
        COUNT_IF("country"             IS NULL OR TRIM("country") = '')             AS missing_country,
        COUNT_IF("acquisition_channel" IS NULL OR TRIM("acquisition_channel") = '') AS missing_acquisition_channel,
        COUNT_IF("registered_at"       IS NULL)                                     AS missing_registered_at,
        COUNT_IF("age_group"           IS NULL)                                     AS missing_age_group,
        COUNT_IF("age_group" IS NOT NULL AND age_group_in_catalog IS NULL)          AS invalid_age_group_format
    FROM users_prep
),

------ 7) issues to rows
issues_long AS (
    -- orders ---------------------------------------------------------
    SELECT 'orders' AS table_name, 'null_in_key_order_id'    AS issue_type, null_in_key_order_id           AS affected_rows FROM orders_profile UNION ALL
    SELECT 'orders', 'null_in_key_user_id',                                 null_in_key_user_id                             FROM orders_profile UNION ALL
    SELECT 'orders', 'null_in_key_product_id',                              null_in_key_product_id                          FROM orders_profile UNION ALL
    SELECT 'orders', 'null_order_date',                                     null_order_date                                 FROM orders_profile UNION ALL
    SELECT 'orders', 'null_status',                                         null_status                                     FROM orders_profile UNION ALL
    SELECT 'orders', 'invalid_status',                                      invalid_status                                  FROM orders_profile UNION ALL
    SELECT 'orders', 'status_inconsistency',                                status_inconsistency                            FROM orders_profile UNION ALL
    SELECT 'orders', 'completed_zero_or_null_revenue',                      completed_zero_or_null_revenue                  FROM orders_profile UNION ALL
    SELECT 'orders', 'quantity_le_zero',                                    quantity_le_zero                                FROM orders_profile UNION ALL
    SELECT 'orders', 'discount_out_of_range',                               discount_out_of_range                           FROM orders_profile UNION ALL
    SELECT 'orders', 'duplicate_order_id',                                  dup_rows                                        FROM dup_orders     UNION ALL
    SELECT 'orders', 'fk_user_id_not_in_users',                             fk_user_id_not_in_users                         FROM orders_fk      UNION ALL
    SELECT 'orders', 'fk_product_id_not_in_products',                       fk_product_id_not_in_products                   FROM orders_fk      UNION ALL
    -- products -------------------------------------------------------
    SELECT 'products', 'null_in_key_product_id',                            null_in_key_product_id                          FROM products_profile UNION ALL
    SELECT 'products', 'duplicate_product_id',                              dup_rows                                        FROM dup_products     UNION ALL
    SELECT 'products', 'price_le_zero',                                     price_le_zero                                   FROM products_profile UNION ALL
    SELECT 'products', 'missing_product_name',                              missing_product_name                            FROM products_profile UNION ALL
    SELECT 'products', 'missing_category',                                  missing_category                                FROM products_profile UNION ALL
    SELECT 'products', 'margin_out_of_range',                               margin_out_of_range                             FROM products_profile UNION ALL
    -- users ----------------------------------------------------------
    SELECT 'users', 'null_in_key_user_id',                                  null_in_key_user_id                             FROM users_profile UNION ALL
    SELECT 'users', 'duplicate_user_id',                                    dup_rows                                        FROM dup_users     UNION ALL
    SELECT 'users', 'missing_country',                                      missing_country                                 FROM users_profile UNION ALL
    SELECT 'users', 'missing_acquisition_channel',                          missing_acquisition_channel                     FROM users_profile UNION ALL
    SELECT 'users', 'missing_registered_at',                                missing_registered_at                           FROM users_profile UNION ALL
    SELECT 'users', 'missing_age_group',                                    missing_age_group                               FROM users_profile UNION ALL
    SELECT 'users', 'invalid_age_group_format',                             invalid_age_group_format                        FROM users_profile
)

-- ---- 8) Final issues 
SELECT
    CAST(i.table_name       AS VARCHAR) AS table_name,
    CAST(i.issue_type       AS VARCHAR) AS issue_type,
    CAST(i.affected_rows    AS NUMBER)  AS affected_rows,
    CAST(c.description      AS VARCHAR) AS description,
    CAST(c.recommended_fix  AS VARCHAR) AS recommended_fix
FROM issues_long i
LEFT JOIN "issue_catalog" c
       ON c.table_name = i.table_name
      AND c.issue_type = i.issue_type
WHERE i.affected_rows > 0
ORDER BY i.table_name, i.issue_type
;
