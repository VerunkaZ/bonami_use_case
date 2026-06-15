-- =====================================================================
-- BLOCK A: stg_orders
-- Output mapping: stg_orders -> out.c-staging.stg_orders (full load)
-- =====================================================================

CREATE OR REPLACE TABLE "stg_orders" AS

WITH
source AS (
    SELECT
        "order_id",
        "user_id",
        "product_id",
        "order_date",
        "quantity",
        "status",
        "revenue_czk",
        "discount_pct"
    FROM "orders"
),

normalized AS (
    SELECT
        "order_id",
        "user_id",
        "product_id",
        "order_date",
        "quantity",

        CASE
            WHEN "status" IS NULL                                              THEN NULL
            WHEN LOWER(TRIM("status")) = 'kompletní'                           THEN 'completed'
            WHEN LOWER(TRIM("status")) IN ('completed','cancelled','returned') THEN LOWER(TRIM("status"))
            ELSE NULL
        END                                                AS "status",

        "revenue_czk",
        "discount_pct",

        CASE
            WHEN LOWER(TRIM("status")) IN ('completed','kompletní')
             AND (NULLIF(TRIM("revenue_czk"), '') IS NULL OR TRY_CAST(NULLIF(TRIM("revenue_czk"), '') AS NUMBER) = 0)
            THEN 1 ELSE 0
        END                                                AS "is_revenue_suspicious",

        CASE
            WHEN "status" IS NOT NULL
             AND LOWER(TRIM("status")) NOT IN ('completed','cancelled','returned','kompletní')
            THEN 1 ELSE 0
        END                                                AS "is_status_unknown",

        CASE
            WHEN NULLIF(TRIM("quantity"), '') IS NULL
              OR TRY_CAST(NULLIF(TRIM("quantity"), '') AS NUMBER) IS NULL
              OR TRY_CAST(NULLIF(TRIM("quantity"), '') AS NUMBER) <= 0
            THEN 1 ELSE 0
        END                                                AS "is_quantity_invalid"
    FROM source
),

dedup AS (
  SELECT
    "order_id","user_id","product_id","order_date","quantity",
    "status","revenue_czk","discount_pct",
    "is_revenue_suspicious","is_status_unknown","is_quantity_invalid",
    ROW_NUMBER() OVER (
      PARTITION BY "order_id"
      ORDER BY
        CASE WHEN "status" = 'completed' THEN 0 ELSE 1 END,
        TRY_CAST(NULLIF(TRIM("order_date"), '') AS DATE) DESC NULLS LAST
    ) AS "rn"
  FROM normalized
)

SELECT
  CAST("order_id"     AS VARCHAR) AS "order_id",
  CAST("user_id"      AS VARCHAR) AS "user_id",
  CAST("product_id"   AS VARCHAR) AS "product_id",
  TRY_CAST(NULLIF(TRIM(CAST("order_date" AS VARCHAR)), '') AS DATE) AS "order_date",
  TRY_CAST(NULLIF(TRIM(CAST("quantity" AS VARCHAR)), '') AS NUMBER) AS "quantity",
  CAST("status"       AS VARCHAR) AS "status",
  TRY_CAST(NULLIF(TRIM(CAST("revenue_czk" AS VARCHAR)), '') AS NUMBER(18,2)) AS "revenue_czk",
  TRY_CAST(NULLIF(TRIM(CAST("discount_pct" AS VARCHAR)), '') AS NUMBER(6,4)) AS "discount_pct",
  CAST("is_revenue_suspicious" AS NUMBER(1)) AS "is_revenue_suspicious",
  CAST("is_status_unknown"     AS NUMBER(1)) AS "is_status_unknown",
  CAST("is_quantity_invalid"   AS NUMBER(1)) AS "is_quantity_invalid",
  CURRENT_TIMESTAMP() AS "loaded_at",
  'orders'            AS "source_table"
FROM dedup
WHERE "rn" = 1;
