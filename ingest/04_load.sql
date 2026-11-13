-- =============================================================================
-- ingest/04_load.sql
-- Load the eight staged CSVs into the RAW tables. Run as ELIO_TRANSFORMER.
-- Run ingest/04_dry_run.py FIRST: it must report 0 error rows for every file.
--
-- One COPY INTO per table (each file maps to exactly one table), generated from the CSV headers.
--
-- The SELECT form is used so each row records where it came from:
--     $1, $2, ...                 the CSV fields, by position (the table has the same column order)
--     METADATA$FILENAME           -> _source_file
--     METADATA$FILE_ROW_NUMBER    -> _source_row
--     METADATA$START_SCAN_TIME    -> _loaded_at  (Snowflake recommends it over a CURRENT_TIMESTAMP default)
--
-- ON_ERROR = ABORT_STATEMENT (written out although it is the default): the first error stops that
-- COPY and loads NOTHING from the file, so a table is never half-loaded and no bad row is silently
-- dropped. All source columns are text, so a failure here means our reading rules are wrong and
-- must be fixed, not skipped.
--
-- NOTE: in the SELECT form Snowflake ignores ERROR_ON_COLUMN_COUNT_MISMATCH. The dry run is what
-- checks the number of fields per row.
--
-- Snowflake remembers which files it has loaded into a table, so re-running this skips them.
-- To reload on purpose, empty the tables first (see ingest/README.md).
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- orders  (8 CSV fields)
COPY INTO ELIO_OLIST.RAW.ORDERS (
    order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_orders_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- order_items  (7 CSV fields)
COPY INTO ELIO_OLIST.RAW.ORDER_ITEMS (
    order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_order_items_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- customers  (5 CSV fields)
COPY INTO ELIO_OLIST.RAW.CUSTOMERS (
    customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_customers_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- order_payments  (5 CSV fields)
COPY INTO ELIO_OLIST.RAW.ORDER_PAYMENTS (
    order_id, payment_sequential, payment_type, payment_installments, payment_value,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_order_payments_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- order_reviews  (7 CSV fields)
COPY INTO ELIO_OLIST.RAW.ORDER_REVIEWS (
    review_id, order_id, review_score, review_comment_title, review_comment_message, review_creation_date, review_answer_timestamp,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_order_reviews_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- products  (9 CSV fields)
COPY INTO ELIO_OLIST.RAW.PRODUCTS (
    product_id, product_category_name, product_name_lenght, product_description_lenght, product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_products_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- sellers  (4 CSV fields)
COPY INTO ELIO_OLIST.RAW.SELLERS (
    seller_id, seller_zip_code_prefix, seller_city, seller_state,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2, $3, $4,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/olist_sellers_dataset.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;

-- product_category_name_translation  (2 CSV fields)
COPY INTO ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION (
    product_category_name, product_category_name_english,
    _source_file, _source_row, _loaded_at)
FROM (
    SELECT $1, $2,
           METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, METADATA$START_SCAN_TIME
    FROM @ELIO_OLIST.RAW.OLIST_STAGE/product_category_name_translation.csv.gz)
FILE_FORMAT = (FORMAT_NAME = 'ELIO_OLIST.RAW.OLIST_CSV')
ON_ERROR = ABORT_STATEMENT;
