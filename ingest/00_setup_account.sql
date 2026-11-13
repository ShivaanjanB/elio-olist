-- =============================================================================
-- ingest/00_setup_account.sql
-- One-off Snowflake setup for the Olist pipeline.
-- Run once in a Snowsight worksheet as ACCOUNTADMIN (the trial's default role).
-- Safe to re-run: every statement is CREATE ... IF NOT EXISTS or a GRANT.
--
-- Creates
--   role       ELIO_TRANSFORMER  owns the pipeline schemas; used by ingest and dbt
--   warehouse  ELIO_WH           X-Small, suspends after 60 s idle
--   database   ELIO_OLIST        RAW schema here; dbt creates STAGING / INTERMEDIATE / MARTS
--   monitor    ELIO_MONITOR      credit cap so a runaway query can't drain the trial
--   user       ELIO_SVC          service user (key-pair only, no password) for scripts, dbt, CI
-- =============================================================================

-- 1. Role -------------------------------------------------------------------
--    SECURITYADMIN manages roles and grants (least privilege: not ACCOUNTADMIN).
USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS ELIO_TRANSFORMER
  COMMENT = 'Loads RAW and builds dbt models for the Olist pipeline';

-- Keep the custom role inside the standard hierarchy so SYSADMIN can see its objects.
GRANT ROLE ELIO_TRANSFORMER TO ROLE SYSADMIN;

-- Let the person running this script use the role in Snowsight too.
SET my_user = CURRENT_USER();
GRANT ROLE ELIO_TRANSFORMER TO USER IDENTIFIER($my_user);

-- 2. Compute and storage ----------------------------------------------------
--    SYSADMIN creates and owns warehouses and databases.
USE ROLE SYSADMIN;

CREATE WAREHOUSE IF NOT EXISTS ELIO_WH
  WAREHOUSE_SIZE      = XSMALL
  AUTO_SUSPEND        = 60      -- seconds idle before it stops billing
  AUTO_RESUME         = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Olist pipeline: ingest and dbt';

CREATE DATABASE IF NOT EXISTS ELIO_OLIST
  COMMENT = 'Olist e-commerce pipeline';

GRANT USAGE, OPERATE ON WAREHOUSE ELIO_WH    TO ROLE ELIO_TRANSFORMER;
GRANT USAGE, CREATE SCHEMA ON DATABASE ELIO_OLIST TO ROLE ELIO_TRANSFORMER;

-- 3. RAW schema, owned by the pipeline role ---------------------------------
--    Created as ELIO_TRANSFORMER so that role owns it (and its stage, file format, tables).
USE ROLE ELIO_TRANSFORMER;

CREATE SCHEMA IF NOT EXISTS ELIO_OLIST.RAW
  COMMENT = 'Olist CSVs loaded as-is, no cleaning';

-- 4. Credit guard-rail ------------------------------------------------------
--    Only ACCOUNTADMIN can create resource monitors.
USE ROLE ACCOUNTADMIN;

CREATE RESOURCE MONITOR IF NOT EXISTS ELIO_MONITOR
  WITH CREDIT_QUOTA    = 20
       FREQUENCY       = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75  PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE ELIO_WH SET RESOURCE_MONITOR = ELIO_MONITOR;

-- 5. Service user for scripts, dbt and CI -----------------------------------
--    TYPE = SERVICE means no password and no MFA prompts: it can only sign in with the key.
--    Replace the placeholder with the one-line public key (see ingest/README.md).
USE ROLE SECURITYADMIN;

CREATE USER IF NOT EXISTS ELIO_SVC
  TYPE              = SERVICE
  DEFAULT_ROLE      = ELIO_TRANSFORMER
  DEFAULT_WAREHOUSE = ELIO_WH
  DEFAULT_NAMESPACE = ELIO_OLIST.RAW
  RSA_PUBLIC_KEY    = '<PASTE_ONE_LINE_PUBLIC_KEY_HERE>'
  COMMENT           = 'Olist pipeline service user: ingest scripts, dbt, CI';

GRANT ROLE ELIO_TRANSFORMER TO USER ELIO_SVC;

-- 6. Check ------------------------------------------------------------------
--    RSA_PUBLIC_KEY_FP should show SHA256:... matching the fingerprint of your key.
DESC USER ELIO_SVC;

-- Key rotation later: ALTER USER ELIO_SVC SET RSA_PUBLIC_KEY_2 = '...'; then unset the old one.
