-- =====================================================================
-- BLOCK B: stg_products
-- Output mapping: stg_products -> out.c-staging.stg_products (full load)
-- =====================================================================
CREATE OR REPLACE TABLE "stg_products" AS

WITH
source AS (
  SELECT "product_id","product_name","category","price_czk","margin_pct","is_active"
  FROM "products"
),

cleaned AS (
  SELECT
    "product_id",
    TRIM("product_name")                                     AS "product_name",
    INITCAP(LOWER(TRIM("category")))                         AS "category",

    TRY_CAST(NULLIF(TRIM(CAST("price_czk"  AS VARCHAR)), '') AS NUMBER(18,2)) AS "price_czk",
    TRY_CAST(NULLIF(TRIM(CAST("margin_pct" AS VARCHAR)), '') AS NUMBER(6,4))  AS "margin_pct",

    CASE
      WHEN LOWER(TRIM(CAST("is_active" AS VARCHAR))) IN ('1','true','t','yes','y','ano') THEN 1
      WHEN LOWER(TRIM(CAST("is_active" AS VARCHAR))) IN ('0','false','f','no','n','ne')  THEN 0
      ELSE NULL
    END AS "is_active",

    CASE WHEN TRY_CAST(NULLIF(TRIM(CAST("price_czk"  AS VARCHAR)), '') AS NUMBER) IS NULL
           OR TRY_CAST(NULLIF(TRIM(CAST("price_czk"  AS VARCHAR)), '') AS NUMBER) <= 0
         THEN 1 ELSE 0 END AS "is_price_invalid",

    CASE WHEN TRY_CAST(NULLIF(TRIM(CAST("margin_pct" AS VARCHAR)), '') AS NUMBER(10,4)) IS NULL
           OR TRY_CAST(NULLIF(TRIM(CAST("margin_pct" AS VARCHAR)), '') AS NUMBER(10,4)) NOT BETWEEN 0 AND 1
         THEN 1 ELSE 0 END AS "is_margin_out_of_range",

    CASE WHEN "category" IS NULL OR TRIM("category") = ''
         THEN 1 ELSE 0 END AS "is_category_missing"
  FROM source
),

dedup AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY "product_id"
      ORDER BY
        CASE WHEN "is_active" = 1 THEN 0 ELSE 1 END,
        "price_czk" DESC NULLS LAST
    ) AS "rn"
  FROM cleaned
)

SELECT
  CAST("product_id"   AS VARCHAR)      AS "product_id",
  CAST("product_name" AS VARCHAR)      AS "product_name",
  CAST("category"     AS VARCHAR)      AS "category",
  CAST("price_czk"    AS NUMBER(18,2)) AS "price_czk",
  CAST("margin_pct"   AS NUMBER(6,4))  AS "margin_pct",
  CAST("is_active"    AS NUMBER(1))    AS "is_active",
  CAST("is_price_invalid"        AS NUMBER(1)) AS "is_price_invalid",
  CAST("is_margin_out_of_range"  AS NUMBER(1)) AS "is_margin_out_of_range",
  CAST("is_category_missing"     AS NUMBER(1)) AS "is_category_missing",
  CURRENT_TIMESTAMP()                  AS "loaded_at",
  'products'                           AS "source_table"
FROM dedup
WHERE "rn" = 1;
