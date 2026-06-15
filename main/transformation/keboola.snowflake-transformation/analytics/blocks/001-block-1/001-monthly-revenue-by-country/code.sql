-- =====================================================================
-- BLOCK A: monthly_revenue_by_country
-- Output mapping: monthly_revenue_by_country -> out.c-analytics.monthly_revenue_by_country
-- =====================================================================

CREATE OR REPLACE TABLE "monthly_revenue_by_country" AS

WITH
-- 1) completed orders on country
base AS (
    SELECT
        DATE_TRUNC('MONTH', o."order_date")::DATE AS "month",
        COALESCE(u."country", 'UNKNOWN')          AS "country",
        o."revenue_czk"
    FROM "stg_orders" o
    LEFT JOIN "stg_users"  u ON o."user_id" = u."user_id"
    WHERE o."status"               = 'completed'
      AND o."is_revenue_suspicious" = 0
      AND o."order_date"            IS NOT NULL
),

-- 2) monthly agregation country.
monthly AS (
    SELECT
        "month",
        "country",
        SUM("revenue_czk") AS "revenue_czk"
    FROM base
    GROUP BY "month", "country"
),

-- 3) the month before by country
with_prev AS (
    SELECT "month", "country", "revenue_czk",
    LAG("revenue_czk") OVER (PARTITION BY "country" ORDER BY "month") AS "prev_month_revenue_czk",
    LAG("month")       OVER (PARTITION BY "country" ORDER BY "month") AS "prev_month"
    FROM monthly
)

-- 4) final select and MoM %, protected from division by zero
SELECT
    CAST("month"                  AS DATE)         AS "month",
    CAST("country"                AS VARCHAR)      AS "country",
    CAST("revenue_czk"            AS NUMBER(18,2)) AS "revenue_czk",
    CAST("prev_month_revenue_czk" AS NUMBER(18,2)) AS "prev_month_revenue_czk",
    CAST(
        CASE
            WHEN "prev_month" IS NULL OR "prev_month" <> DATEADD('month', -1, "month") THEN NULL
            WHEN "prev_month_revenue_czk" IS NULL OR "prev_month_revenue_czk" = 0 THEN NULL
            ELSE ROUND(("revenue_czk" - "prev_month_revenue_czk") / "prev_month_revenue_czk" * 100, 2)
        END
        AS NUMBER(10,2)
    ) AS "mom_growth_pct"
FROM with_prev
ORDER BY "country", "month"
;
