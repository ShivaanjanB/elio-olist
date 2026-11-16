-- The eight RAW tables: one per CSV file.

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- orders: one row per order  (source: olist_orders_dataset.csv, 8 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.ORDERS (
  order_id                       VARCHAR,
  customer_id                    VARCHAR,
  order_status                   VARCHAR,
  order_purchase_timestamp       VARCHAR,
  order_approved_at              VARCHAR,
  order_delivered_carrier_date   VARCHAR,
  order_delivered_customer_date  VARCHAR,
  order_estimated_delivery_date  VARCHAR,
  _source_file                   VARCHAR,                                    -- METADATA$FILENAME
  _source_row                    NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at                     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_orders_dataset.csv: one row per order';

-- order_items: one row per unit (item) on an order  (source: olist_order_items_dataset.csv, 7 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.ORDER_ITEMS (
  order_id             VARCHAR,
  order_item_id        VARCHAR,
  product_id           VARCHAR,
  seller_id            VARCHAR,
  shipping_limit_date  VARCHAR,
  price                VARCHAR,
  freight_value        VARCHAR,
  _source_file         VARCHAR,                                    -- METADATA$FILENAME
  _source_row          NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at           TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_order_items_dataset.csv: one row per unit (item) on an order';

-- customers: one row per customer_id, which is new on every order; customer_unique_id identifies the person  (source: olist_customers_dataset.csv, 5 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.CUSTOMERS (
  customer_id               VARCHAR,
  customer_unique_id        VARCHAR,
  customer_zip_code_prefix  VARCHAR,
  customer_city             VARCHAR,
  customer_state            VARCHAR,
  _source_file              VARCHAR,                                    -- METADATA$FILENAME
  _source_row               NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at                TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_customers_dataset.csv: one row per customer_id, which is new on every order; customer_unique_id identifies the person';

-- order_payments: one row per payment on an order  (source: olist_order_payments_dataset.csv, 5 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.ORDER_PAYMENTS (
  order_id              VARCHAR,
  payment_sequential    VARCHAR,
  payment_type          VARCHAR,
  payment_installments  VARCHAR,
  payment_value         VARCHAR,
  _source_file          VARCHAR,                                    -- METADATA$FILENAME
  _source_row           NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at            TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_order_payments_dataset.csv: one row per payment on an order';

-- order_reviews: one row per review of an order  (source: olist_order_reviews_dataset.csv, 7 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.ORDER_REVIEWS (
  review_id                VARCHAR,
  order_id                 VARCHAR,
  review_score             VARCHAR,
  review_comment_title     VARCHAR,
  review_comment_message   VARCHAR,
  review_creation_date     VARCHAR,
  review_answer_timestamp  VARCHAR,
  _source_file             VARCHAR,                                    -- METADATA$FILENAME
  _source_row              NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_order_reviews_dataset.csv: one row per review of an order';

-- products: one row per product  (source: olist_products_dataset.csv, 9 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.PRODUCTS (
  product_id                  VARCHAR,
  product_category_name       VARCHAR,
  product_name_lenght         VARCHAR,
  product_description_lenght  VARCHAR,
  product_photos_qty          VARCHAR,
  product_weight_g            VARCHAR,
  product_length_cm           VARCHAR,
  product_height_cm           VARCHAR,
  product_width_cm            VARCHAR,
  _source_file                VARCHAR,                                    -- METADATA$FILENAME
  _source_row                 NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at                  TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_products_dataset.csv: one row per product';

-- sellers: one row per seller  (source: olist_sellers_dataset.csv, 4 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.SELLERS (
  seller_id               VARCHAR,
  seller_zip_code_prefix  VARCHAR,
  seller_city             VARCHAR,
  seller_state            VARCHAR,
  _source_file            VARCHAR,                                    -- METADATA$FILENAME
  _source_row             NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at              TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of olist_sellers_dataset.csv: one row per seller';

-- product_category_name_translation: one row per product category: Portuguese name and English name  (source: product_category_name_translation.csv, 2 columns)
CREATE TABLE IF NOT EXISTS ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION (
  product_category_name          VARCHAR,
  product_category_name_english  VARCHAR,
  _source_file                   VARCHAR,                                    -- METADATA$FILENAME
  _source_row                    NUMBER,                                     -- METADATA$FILE_ROW_NUMBER
  _loaded_at                     TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()   -- when this row was loaded
)
COMMENT = 'Raw copy of product_category_name_translation.csv: one row per product category: Portuguese name and English name';
