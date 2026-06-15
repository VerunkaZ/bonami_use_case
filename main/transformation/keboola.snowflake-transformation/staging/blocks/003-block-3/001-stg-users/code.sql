-- =====================================================================
-- BLOCK C: stg_users
-- Output mapping: stg_users -> out.c-staging.stg_users (full load)
-- =====================================================================
CREATE OR REPLACE TABLE "stg_users" AS

WITH
source AS (
  SELECT "user_id","country","acquisition_channel","registered_at","age_group"
  FROM "users"
),

cleaned AS (
  SELECT
    "user_id",

    CASE WHEN UPPER(TRIM("country")) IN ('CZ','SK','PL','HU','RO')
         THEN UPPER(TRIM("country")) ELSE NULL END                    AS "country",

    LOWER(TRIM("acquisition_channel"))                                AS "acquisition_channel",

    TRY_CAST(NULLIF(TRIM(CAST("registered_at" AS VARCHAR)), '') AS DATE) AS "registered_at",

    CASE
      WHEN TRIM("age_group") IN ('18-24','25-34','35-44','45-54','55+')
      THEN TRIM("age_group")
      ELSE 'unknown'
    END                                                                AS "age_group",

    CASE
      WHEN "age_group" IS NULL
        OR TRIM("age_group") NOT IN ('18-24','25-34','35-44','45-54','55+')
      THEN 1 ELSE 0
    END                                                                AS "is_age_group_unknown",

    CASE WHEN UPPER(TRIM("country")) NOT IN ('CZ','SK','PL','HU','RO') OR "country" IS NULL
         THEN 1 ELSE 0 END                                             AS "is_country_unknown",

    CASE WHEN LOWER(TRIM("acquisition_channel")) NOT IN
              ('paid_search','direct','organic','email','social')
              OR "acquisition_channel" IS NULL
         THEN 1 ELSE 0 END                                             AS "is_channel_unknown",

    CASE WHEN TRY_CAST(NULLIF(TRIM(CAST("registered_at" AS VARCHAR)), '') AS DATE) IS NULL
         THEN 1 ELSE 0 END                                             AS "is_registered_at_invalid"
  FROM source
),

dedup AS (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY "user_id"
      ORDER BY "registered_at" DESC NULLS LAST
    ) AS "rn"
  FROM cleaned
)

SELECT
  CAST("user_id"                  AS VARCHAR)   AS "user_id",
  CAST("country"                  AS VARCHAR)   AS "country",
  CAST("acquisition_channel"      AS VARCHAR)   AS "acquisition_channel",
  CAST("registered_at"            AS DATE)      AS "registered_at",
  CAST("age_group"                AS VARCHAR)   AS "age_group",
  CAST("is_age_group_unknown"     AS NUMBER(1)) AS "is_age_group_unknown",
  CAST("is_country_unknown"       AS NUMBER(1)) AS "is_country_unknown",
  CAST("is_channel_unknown"       AS NUMBER(1)) AS "is_channel_unknown",
  CAST("is_registered_at_invalid" AS NUMBER(1)) AS "is_registered_at_invalid",
  CURRENT_TIMESTAMP()                           AS "loaded_at",
  'users'                                       AS "source_table"
FROM dedup
WHERE "rn" = 1;
