-- =====================================================================
-- BLOCK C: user_segments
-- Output mapping: user_segments -> out.c-analytics.user_segments
-- =====================================================================

CREATE OR REPLACE TABLE "user_segments" AS

WITH
-- 1) reference date = the newest order - instead of current_date (not actual data).
ref AS (
    SELECT MAX("order_date") AS "as_of_date"
    FROM "stg_orders"
),

-- 2) Per-user metrics.
--    filtered left join on users without completed order clausule
user_metrics AS (
    SELECT
        u."user_id",
        u."country",
        u."age_group",
        u."registered_at",
        COUNT(o."order_id")               AS "order_count",
        COALESCE(SUM(o."revenue_czk"), 0) AS "total_revenue_czk",
        MAX(o."order_date")               AS "last_order_date"
    FROM "stg_users" u
    LEFT JOIN "stg_orders" o
           ON o."user_id"                = u."user_id"
          AND o."status"                 = 'completed'
          AND o."is_revenue_suspicious"  = 0
    GROUP BY u."user_id", u."country", u."age_group", u."registered_at"
),

-- 3) adding reference date on users
with_recency AS (
    SELECT
        m.*,
        r."as_of_date",
        DATEDIFF('day', m."registered_at",  r."as_of_date") AS "days_since_registered",
        CASE
            WHEN m."last_order_date" IS NULL THEN NULL
            ELSE DATEDIFF('day', m."last_order_date", r."as_of_date")
        END AS "days_since_last_order"
    FROM user_metrics m
    CROSS JOIN ref r
),

-- 4) segments by rules
--    1) lost          - never bouht or more than a year didn't buy
--    2) high_value    - revenue > 20 000 CZK 
--    3) at_risk       - last buy before 180-365 days
--    4) new_user      - registration < 180 days
--    5) regular       - the rest
segmented AS (
    SELECT
        *,
        CASE
            WHEN "last_order_date" IS NULL OR "days_since_last_order" > 365 THEN 'lost'
            WHEN "total_revenue_czk" > 20000 THEN 'high_value'
            WHEN "days_since_last_order" > 180 THEN 'at_risk'
            WHEN "days_since_registered" < 180 THEN 'new_user'
            ELSE 'regular'
        END AS "segment"
    FROM with_recency
)

SELECT
    CAST("user_id"               AS VARCHAR)      AS "user_id",
    CAST("country"               AS VARCHAR)      AS "country",
    CAST("age_group"             AS VARCHAR)      AS "age_group",
    CAST("registered_at"         AS DATE)         AS "registered_at",
    CAST("last_order_date"       AS DATE)         AS "last_order_date",
    CAST("order_count"           AS NUMBER(38,0)) AS "order_count",
    CAST("total_revenue_czk"     AS NUMBER(18,2)) AS "total_revenue_czk",
    CAST("days_since_registered" AS NUMBER(38,0)) AS "days_since_registered",
    CAST("days_since_last_order" AS NUMBER(38,0)) AS "days_since_last_order",
    CAST("segment"               AS VARCHAR)      AS "segment"
FROM segmented
ORDER BY "segment", "total_revenue_czk" DESC
;
