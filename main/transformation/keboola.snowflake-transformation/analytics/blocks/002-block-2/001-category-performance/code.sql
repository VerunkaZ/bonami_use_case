-- =====================================================================
-- BLOCK B: category_performance
-- Output mapping: category_performance -> out.c-analytics.category_performance
-- =====================================================================

CREATE OR REPLACE TABLE "category_performance" AS

WITH
-- 1) completed orders on category
base AS (
    SELECT
        p."category",
        p."margin_pct",
        o."order_id",
        o."revenue_czk",
        o."discount_pct"
    FROM "stg_orders"   o
    JOIN "stg_products" p ON o."product_id" = p."product_id"
    WHERE o."status"               = 'completed'
      AND o."is_revenue_suspicious" = 0
      AND p."category"              IS NOT NULL
),

-- 2) Categories agregated
agg AS (
    SELECT
        "category",
        SUM("revenue_czk")          AS "total_revenue_czk",
        AVG("margin_pct")           AS "avg_margin_pct",      --- průměr přes objednávky
        COUNT(DISTINCT "order_id")  AS "order_count",
        AVG("discount_pct")         AS "avg_discount_pct"
    FROM base
    GROUP BY "category"
)

-- 3) final select + rank (1 = the highest sale).
SELECT
    CAST("category"                   AS VARCHAR)      AS "category",
    CAST("total_revenue_czk"          AS NUMBER(18,2)) AS "total_revenue_czk",
    CAST(ROUND("avg_margin_pct",   4) AS NUMBER(5,4))  AS "avg_margin_pct",
    CAST("order_count"                AS NUMBER(38,0)) AS "order_count",
    CAST(ROUND("avg_discount_pct", 4) AS NUMBER(5,4))  AS "avg_discount_pct",
    CAST(RANK() OVER (ORDER BY "total_revenue_czk" DESC) AS NUMBER(38,0)) AS "revenue_rank"
FROM agg
ORDER BY "revenue_rank"
;
