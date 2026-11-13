-- =============================================================================
-- ingest/05_check_loaded_data.sql
-- Read-only checks on the loaded RAW tables. Run as ELIO_TRANSFORMER.
-- Each section tests an ASSUMPTION written down in ingest/LOAD_NOTES.md.
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- 1. Windows line endings: a stray carriage return (\r) at the end of the LAST field of a row would
--    mean the default record delimiter did not handle CRLF. Expect 0 everywhere.
SELECT 'orders'          AS tbl, COUNT_IF(order_estimated_delivery_date LIKE '%' || CHR(13) || '%') AS rows_with_stray_cr FROM ELIO_OLIST.RAW.ORDERS
UNION ALL SELECT 'order_items',    COUNT_IF(freight_value          LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.ORDER_ITEMS
UNION ALL SELECT 'customers',      COUNT_IF(customer_state         LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.CUSTOMERS
UNION ALL SELECT 'order_payments', COUNT_IF(payment_value         LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
UNION ALL SELECT 'order_reviews',  COUNT_IF(review_answer_timestamp LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.ORDER_REVIEWS
UNION ALL SELECT 'products',       COUNT_IF(product_width_cm      LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.PRODUCTS
UNION ALL SELECT 'sellers',        COUNT_IF(seller_state          LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.SELLERS
UNION ALL SELECT 'category_translation', COUNT_IF(product_category_name_english LIKE '%' || CHR(13) || '%') FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
ORDER BY 1;

-- 2. Blanks: a blank field should load as NULL (EMPTY_FIELD_AS_NULL), not as an empty string.
--    Lists every column that has any NULLs or any empty strings. "empty_text" > 0 would mean
--    some blanks came through as '' instead of NULL.
SELECT * FROM (
  SELECT 'ORDERS' AS tbl, 'order_id' AS col, COUNT_IF(order_id IS NULL) AS nulls, COUNT_IF(order_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'customer_id' AS col, COUNT_IF(customer_id IS NULL) AS nulls, COUNT_IF(customer_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_status' AS col, COUNT_IF(order_status IS NULL) AS nulls, COUNT_IF(order_status = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_purchase_timestamp' AS col, COUNT_IF(order_purchase_timestamp IS NULL) AS nulls, COUNT_IF(order_purchase_timestamp = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_approved_at' AS col, COUNT_IF(order_approved_at IS NULL) AS nulls, COUNT_IF(order_approved_at = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_delivered_carrier_date' AS col, COUNT_IF(order_delivered_carrier_date IS NULL) AS nulls, COUNT_IF(order_delivered_carrier_date = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_delivered_customer_date' AS col, COUNT_IF(order_delivered_customer_date IS NULL) AS nulls, COUNT_IF(order_delivered_customer_date = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDERS' AS tbl, 'order_estimated_delivery_date' AS col, COUNT_IF(order_estimated_delivery_date IS NULL) AS nulls, COUNT_IF(order_estimated_delivery_date = '') AS empty_text FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'order_id' AS col, COUNT_IF(order_id IS NULL) AS nulls, COUNT_IF(order_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'order_item_id' AS col, COUNT_IF(order_item_id IS NULL) AS nulls, COUNT_IF(order_item_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'product_id' AS col, COUNT_IF(product_id IS NULL) AS nulls, COUNT_IF(product_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'seller_id' AS col, COUNT_IF(seller_id IS NULL) AS nulls, COUNT_IF(seller_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'shipping_limit_date' AS col, COUNT_IF(shipping_limit_date IS NULL) AS nulls, COUNT_IF(shipping_limit_date = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'price' AS col, COUNT_IF(price IS NULL) AS nulls, COUNT_IF(price = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'ORDER_ITEMS' AS tbl, 'freight_value' AS col, COUNT_IF(freight_value IS NULL) AS nulls, COUNT_IF(freight_value = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'CUSTOMERS' AS tbl, 'customer_id' AS col, COUNT_IF(customer_id IS NULL) AS nulls, COUNT_IF(customer_id = '') AS empty_text FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'CUSTOMERS' AS tbl, 'customer_unique_id' AS col, COUNT_IF(customer_unique_id IS NULL) AS nulls, COUNT_IF(customer_unique_id = '') AS empty_text FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'CUSTOMERS' AS tbl, 'customer_zip_code_prefix' AS col, COUNT_IF(customer_zip_code_prefix IS NULL) AS nulls, COUNT_IF(customer_zip_code_prefix = '') AS empty_text FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'CUSTOMERS' AS tbl, 'customer_city' AS col, COUNT_IF(customer_city IS NULL) AS nulls, COUNT_IF(customer_city = '') AS empty_text FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'CUSTOMERS' AS tbl, 'customer_state' AS col, COUNT_IF(customer_state IS NULL) AS nulls, COUNT_IF(customer_state = '') AS empty_text FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'ORDER_PAYMENTS' AS tbl, 'order_id' AS col, COUNT_IF(order_id IS NULL) AS nulls, COUNT_IF(order_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'ORDER_PAYMENTS' AS tbl, 'payment_sequential' AS col, COUNT_IF(payment_sequential IS NULL) AS nulls, COUNT_IF(payment_sequential = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'ORDER_PAYMENTS' AS tbl, 'payment_type' AS col, COUNT_IF(payment_type IS NULL) AS nulls, COUNT_IF(payment_type = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'ORDER_PAYMENTS' AS tbl, 'payment_installments' AS col, COUNT_IF(payment_installments IS NULL) AS nulls, COUNT_IF(payment_installments = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'ORDER_PAYMENTS' AS tbl, 'payment_value' AS col, COUNT_IF(payment_value IS NULL) AS nulls, COUNT_IF(payment_value = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_id' AS col, COUNT_IF(review_id IS NULL) AS nulls, COUNT_IF(review_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'order_id' AS col, COUNT_IF(order_id IS NULL) AS nulls, COUNT_IF(order_id = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_score' AS col, COUNT_IF(review_score IS NULL) AS nulls, COUNT_IF(review_score = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_comment_title' AS col, COUNT_IF(review_comment_title IS NULL) AS nulls, COUNT_IF(review_comment_title = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_comment_message' AS col, COUNT_IF(review_comment_message IS NULL) AS nulls, COUNT_IF(review_comment_message = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_creation_date' AS col, COUNT_IF(review_creation_date IS NULL) AS nulls, COUNT_IF(review_creation_date = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'ORDER_REVIEWS' AS tbl, 'review_answer_timestamp' AS col, COUNT_IF(review_answer_timestamp IS NULL) AS nulls, COUNT_IF(review_answer_timestamp = '') AS empty_text FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_id' AS col, COUNT_IF(product_id IS NULL) AS nulls, COUNT_IF(product_id = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_category_name' AS col, COUNT_IF(product_category_name IS NULL) AS nulls, COUNT_IF(product_category_name = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_name_lenght' AS col, COUNT_IF(product_name_lenght IS NULL) AS nulls, COUNT_IF(product_name_lenght = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_description_lenght' AS col, COUNT_IF(product_description_lenght IS NULL) AS nulls, COUNT_IF(product_description_lenght = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_photos_qty' AS col, COUNT_IF(product_photos_qty IS NULL) AS nulls, COUNT_IF(product_photos_qty = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_weight_g' AS col, COUNT_IF(product_weight_g IS NULL) AS nulls, COUNT_IF(product_weight_g = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_length_cm' AS col, COUNT_IF(product_length_cm IS NULL) AS nulls, COUNT_IF(product_length_cm = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_height_cm' AS col, COUNT_IF(product_height_cm IS NULL) AS nulls, COUNT_IF(product_height_cm = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'PRODUCTS' AS tbl, 'product_width_cm' AS col, COUNT_IF(product_width_cm IS NULL) AS nulls, COUNT_IF(product_width_cm = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'SELLERS' AS tbl, 'seller_id' AS col, COUNT_IF(seller_id IS NULL) AS nulls, COUNT_IF(seller_id = '') AS empty_text FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL
  SELECT 'SELLERS' AS tbl, 'seller_zip_code_prefix' AS col, COUNT_IF(seller_zip_code_prefix IS NULL) AS nulls, COUNT_IF(seller_zip_code_prefix = '') AS empty_text FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL
  SELECT 'SELLERS' AS tbl, 'seller_city' AS col, COUNT_IF(seller_city IS NULL) AS nulls, COUNT_IF(seller_city = '') AS empty_text FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL
  SELECT 'SELLERS' AS tbl, 'seller_state' AS col, COUNT_IF(seller_state IS NULL) AS nulls, COUNT_IF(seller_state = '') AS empty_text FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL
  SELECT 'PRODUCT_CATEGORY_NAME_TRANSLATION' AS tbl, 'product_category_name' AS col, COUNT_IF(product_category_name IS NULL) AS nulls, COUNT_IF(product_category_name = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
  UNION ALL
  SELECT 'PRODUCT_CATEGORY_NAME_TRANSLATION' AS tbl, 'product_category_name_english' AS col, COUNT_IF(product_category_name_english IS NULL) AS nulls, COUNT_IF(product_category_name_english = '') AS empty_text FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
) WHERE nulls > 0 OR empty_text > 0
ORDER BY tbl, col;

-- 3. Zip prefixes must keep their leading zeros: all 5 characters long, and some start with 0.
SELECT 'customers' AS tbl, COUNT(*) AS total_rows,
       COUNT_IF(LENGTH(customer_zip_code_prefix) <> 5) AS not_5_characters,
       COUNT_IF(customer_zip_code_prefix LIKE '0%')    AS starting_with_0
FROM ELIO_OLIST.RAW.CUSTOMERS
UNION ALL
SELECT 'sellers', COUNT(*), COUNT_IF(LENGTH(seller_zip_code_prefix) <> 5), COUNT_IF(seller_zip_code_prefix LIKE '0%')
FROM ELIO_OLIST.RAW.SELLERS;

-- 4. Portuguese accents: how many values contain non-ASCII characters (multi-byte = LENGTH differs
--    from OCTET_LENGTH), and how many show the telltale garbling of a wrong encoding (a capital A with a
--    tilde, CHR(195), followed by a symbol: what e-acute, a-tilde and c-cedilla become when misread).
--    Expect many accented values and 0 garbled ones.
SELECT 'order_reviews.review_comment_message' AS col,
       COUNT_IF(LENGTH(review_comment_message) <> OCTET_LENGTH(review_comment_message)) AS values_with_accents,
       COUNT_IF(review_comment_message LIKE '%' || CHR(195) || CHR(169) || '%'
             OR review_comment_message LIKE '%' || CHR(195) || CHR(163) || '%'
             OR review_comment_message LIKE '%' || CHR(195) || CHR(167) || '%') AS garbled_values
FROM ELIO_OLIST.RAW.ORDER_REVIEWS
UNION ALL
SELECT 'order_reviews.review_comment_title',
       COUNT_IF(LENGTH(review_comment_title) <> OCTET_LENGTH(review_comment_title)),
       COUNT_IF(review_comment_title LIKE '%' || CHR(195) || CHR(169) || '%'
             OR review_comment_title LIKE '%' || CHR(195) || CHR(163) || '%'
             OR review_comment_title LIKE '%' || CHR(195) || CHR(167) || '%')
FROM ELIO_OLIST.RAW.ORDER_REVIEWS
UNION ALL
SELECT 'sellers.seller_city',
       COUNT_IF(LENGTH(seller_city) <> OCTET_LENGTH(seller_city)),
       COUNT_IF(seller_city LIKE '%' || CHR(195) || CHR(169) || '%' OR seller_city LIKE '%' || CHR(195) || CHR(163) || '%')
FROM ELIO_OLIST.RAW.SELLERS
UNION ALL
SELECT 'customers.customer_city',
       COUNT_IF(LENGTH(customer_city) <> OCTET_LENGTH(customer_city)),
       COUNT_IF(customer_city LIKE '%' || CHR(195) || CHR(169) || '%' OR customer_city LIKE '%' || CHR(195) || CHR(163) || '%')
FROM ELIO_OLIST.RAW.CUSTOMERS;

-- 5. Facts found when profiling the raw CSVs (ingest/README.md), reproduced from the loaded tables.
--    RAW must hold exactly what the files held, duplicates and all.
SELECT fact, expected, actual, IFF(expected = actual, 'OK', 'DIFFERENT') AS result FROM (
  SELECT 'orders: distinct statuses' AS fact, 8 AS expected,
         (SELECT COUNT(DISTINCT order_status) FROM ELIO_OLIST.RAW.ORDERS) AS actual
  UNION ALL SELECT 'orders: status delivered', 96478,
         (SELECT COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_status = 'delivered')
  UNION ALL SELECT 'orders: blank customer-delivery dates', 2965,
         (SELECT COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_delivered_customer_date IS NULL)
  UNION ALL SELECT 'orders: blank approval times', 160,
         (SELECT COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_approved_at IS NULL)
  UNION ALL SELECT 'order_items: distinct (order_id, order_item_id)', 112650,
         (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM ELIO_OLIST.RAW.ORDER_ITEMS))
  UNION ALL SELECT 'customers: distinct customer_id', 99441,
         (SELECT COUNT(DISTINCT customer_id) FROM ELIO_OLIST.RAW.CUSTOMERS)
  UNION ALL SELECT 'customers: distinct customer_unique_id (people)', 96096,
         (SELECT COUNT(DISTINCT customer_unique_id) FROM ELIO_OLIST.RAW.CUSTOMERS)
  UNION ALL SELECT 'customers: people who appear more than once', 2997,
         (SELECT COUNT(*) FROM (SELECT customer_unique_id FROM ELIO_OLIST.RAW.CUSTOMERS GROUP BY 1 HAVING COUNT(*) > 1))
  UNION ALL SELECT 'order_payments: payment_type not_defined', 3,
         (SELECT COUNT(*) FROM ELIO_OLIST.RAW.ORDER_PAYMENTS WHERE payment_type = 'not_defined')
  UNION ALL SELECT 'order_payments: distinct (order_id, payment_sequential)', 103886,
         (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM ELIO_OLIST.RAW.ORDER_PAYMENTS))
  UNION ALL SELECT 'order_reviews: review_ids that repeat', 789,
         (SELECT COUNT(*) FROM (SELECT review_id FROM ELIO_OLIST.RAW.ORDER_REVIEWS GROUP BY 1 HAVING COUNT(*) > 1))
  UNION ALL SELECT 'order_reviews: orders with more than one review', 547,
         (SELECT COUNT(*) FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_REVIEWS GROUP BY 1 HAVING COUNT(*) > 1))
  UNION ALL SELECT 'order_reviews: distinct (review_id, order_id)', 99224,
         (SELECT COUNT(*) FROM (SELECT DISTINCT review_id, order_id FROM ELIO_OLIST.RAW.ORDER_REVIEWS))
  UNION ALL SELECT 'products: blank category', 610,
         (SELECT COUNT(*) FROM ELIO_OLIST.RAW.PRODUCTS WHERE product_category_name IS NULL)
)
ORDER BY fact;