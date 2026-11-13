-- =============================================================================
-- ingest/truncate_raw_tables.sql
-- Empty the eight RAW tables so they can be rebuilt from the staged files.
-- Run as ELIO_TRANSFORMER. DESTRUCTIVE for the table rows (the staged files are untouched), which
-- is safe here because RAW is only ever a copy of the files on the stage.
--
-- Rebuild path:   truncate_raw_tables.sql  ->  04_dry_run.py  ->  04_load.sql  ->  05_reconcile.py
--
-- (If a staged file is missing, run ingest/02_upload_files.py first.)
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

TRUNCATE TABLE ELIO_OLIST.RAW.ORDERS;
TRUNCATE TABLE ELIO_OLIST.RAW.ORDER_ITEMS;
TRUNCATE TABLE ELIO_OLIST.RAW.CUSTOMERS;
TRUNCATE TABLE ELIO_OLIST.RAW.ORDER_PAYMENTS;
TRUNCATE TABLE ELIO_OLIST.RAW.ORDER_REVIEWS;
TRUNCATE TABLE ELIO_OLIST.RAW.PRODUCTS;
TRUNCATE TABLE ELIO_OLIST.RAW.SELLERS;
TRUNCATE TABLE ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION;
