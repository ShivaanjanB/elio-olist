-- =============================================================================
-- docs/type_and_design_checks.sql
-- Evidence for the type and design decisions in docs/data_model.md and docs/decision_log.md.
-- Read-only. Run as ELIO_TRANSFORMER:
--   .\.venv\Scripts\python.exe ingest\run_sql.py docs\type_and_design_checks.sql
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- 1. IDs: are they all 32 characters (so VARCHAR(32) is safe)?
SELECT col, COUNT(*) AS rows_checked, COUNT_IF(v IS NULL) AS nulls, COUNT_IF(LENGTH(v) <> 32) AS not_32_characters FROM (
  SELECT 'orders.order_id' AS col, order_id AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'orders.customer_id' AS col, customer_id AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'customers.customer_id' AS col, customer_id AS v FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'customers.customer_unique_id' AS col, customer_unique_id AS v FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL
  SELECT 'order_items.order_id' AS col, order_id AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_items.product_id' AS col, product_id AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_items.seller_id' AS col, seller_id AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_payments.order_id' AS col, order_id AS v FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'order_reviews.review_id' AS col, review_id AS v FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'order_reviews.order_id' AS col, order_id AS v FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'products.product_id' AS col, product_id AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'sellers.seller_id' AS col, seller_id AS v FROM ELIO_OLIST.RAW.SELLERS
) GROUP BY col ORDER BY col;

-- 2. Timestamps: do all non-blank values parse as YYYY-MM-DD HH24:MI:SS?
SELECT col, COUNT(v) AS non_blank, COUNT_IF(v IS NOT NULL AND TRY_TO_TIMESTAMP_NTZ(v, 'YYYY-MM-DD HH24:MI:SS') IS NULL) AS unparseable FROM (
  SELECT 'orders.order_purchase_timestamp' AS col, order_purchase_timestamp AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'orders.order_approved_at' AS col, order_approved_at AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'orders.order_delivered_carrier_date' AS col, order_delivered_carrier_date AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'orders.order_delivered_customer_date' AS col, order_delivered_customer_date AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'orders.order_estimated_delivery_date' AS col, order_estimated_delivery_date AS v FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL
  SELECT 'order_items.shipping_limit_date' AS col, shipping_limit_date AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_reviews.review_creation_date' AS col, review_creation_date AS v FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'order_reviews.review_answer_timestamp' AS col, review_answer_timestamp AS v FROM ELIO_OLIST.RAW.ORDER_REVIEWS
) GROUP BY col ORDER BY col;

-- 3. Money: parse as NUMBER(12,2)? Any value with more than 2 decimals (which NUMBER(12,2) would round)?
SELECT col, COUNT(v) AS non_blank, COUNT_IF(v IS NOT NULL AND TRY_TO_NUMBER(v, 12, 2) IS NULL) AS unparseable, COUNT_IF(LENGTH(SPLIT_PART(v, '.', 2)) > 2) AS more_than_2_decimals, MIN(TRY_TO_NUMBER(v, 12, 2)) AS min_value, MAX(TRY_TO_NUMBER(v, 12, 2)) AS max_value FROM (
  SELECT 'order_items.price' AS col, price AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_items.freight_value' AS col, freight_value AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_payments.payment_value' AS col, payment_value AS v FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
) GROUP BY col ORDER BY col;

-- 4. Whole numbers: parse? Any decimal point (which would mean they are not whole)? Range?
SELECT col, COUNT(v) AS non_blank, COUNT_IF(v IS NOT NULL AND TRY_TO_DECIMAL(v, 18, 4) IS NULL) AS unparseable, COUNT_IF(v LIKE '%.%') AS has_decimal_point, MIN(TRY_TO_DECIMAL(v, 18, 4)) AS min_value, MAX(TRY_TO_DECIMAL(v, 18, 4)) AS max_value FROM (
  SELECT 'order_items.order_item_id' AS col, order_item_id AS v FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL
  SELECT 'order_payments.payment_sequential' AS col, payment_sequential AS v FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'order_payments.payment_installments' AS col, payment_installments AS v FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL
  SELECT 'order_reviews.review_score' AS col, review_score AS v FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL
  SELECT 'products.product_photos_qty' AS col, product_photos_qty AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_name_lenght' AS col, product_name_lenght AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_description_lenght' AS col, product_description_lenght AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_weight_g' AS col, product_weight_g AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_length_cm' AS col, product_length_cm AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_height_cm' AS col, product_height_cm AS v FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL
  SELECT 'products.product_width_cm' AS col, product_width_cm AS v FROM ELIO_OLIST.RAW.PRODUCTS
) GROUP BY col ORDER BY col;

-- 5. Short codes and lists of values.
SELECT 'customers.customer_state' AS col, COUNT(*) AS rows_checked, COUNT_IF(LENGTH(customer_state) <> 2) AS not_2_characters, COUNT(DISTINCT customer_state) AS distinct_values FROM ELIO_OLIST.RAW.CUSTOMERS
UNION ALL SELECT 'sellers.seller_state', COUNT(*), COUNT_IF(LENGTH(seller_state) <> 2), COUNT(DISTINCT seller_state) FROM ELIO_OLIST.RAW.SELLERS;
SELECT payment_type, COUNT(*) AS payments FROM ELIO_OLIST.RAW.ORDER_PAYMENTS GROUP BY 1 ORDER BY 2 DESC;
SELECT review_score, COUNT(*) AS reviews FROM ELIO_OLIST.RAW.ORDER_REVIEWS GROUP BY 1 ORDER BY 1;

-- 6. Longest values (to decide whether a length limit is worth declaring).
SELECT 'customers.customer_city' AS col, MAX(LENGTH(customer_city)) AS longest FROM ELIO_OLIST.RAW.CUSTOMERS
UNION ALL SELECT 'sellers.seller_city', MAX(LENGTH(seller_city)) FROM ELIO_OLIST.RAW.SELLERS
UNION ALL SELECT 'products.product_category_name', MAX(LENGTH(product_category_name)) FROM ELIO_OLIST.RAW.PRODUCTS
UNION ALL SELECT 'category translation english name', MAX(LENGTH(product_category_name_english)) FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION;

-- 7. Estimated delivery dates: do they all sit at midnight? (decides at what grain "late" is measured)
SELECT COUNT(*) AS orders, COUNT_IF(order_estimated_delivery_date NOT LIKE '% 00:00:00') AS estimated_not_at_midnight
FROM ELIO_OLIST.RAW.ORDERS;

-- 8. A person with several customer_ids: do their city/state/zip differ? (decides which location the person dimension carries)
SELECT COUNT(*) AS people_with_more_than_one_customer_id,
       COUNT_IF(states > 1) AS with_different_states, COUNT_IF(zips > 1) AS with_different_zips, COUNT_IF(cities > 1) AS with_different_cities
FROM (SELECT customer_unique_id, COUNT(*) AS ids, COUNT(DISTINCT customer_state) AS states,
             COUNT(DISTINCT customer_zip_code_prefix) AS zips, COUNT(DISTINCT customer_city) AS cities
      FROM ELIO_OLIST.RAW.CUSTOMERS GROUP BY 1 HAVING COUNT(*) > 1);

-- 9. First order of a person: does any person have two orders at exactly the same first timestamp? (needs a tie-break)
WITH o AS (SELECT c.customer_unique_id AS uid, o.order_purchase_timestamp AS ts
           FROM ELIO_OLIST.RAW.ORDERS o JOIN ELIO_OLIST.RAW.CUSTOMERS c ON c.customer_id = o.customer_id),
ranked AS (SELECT uid, ts, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ts) AS rn, COUNT(*) OVER (PARTITION BY uid, ts) AS same_ts FROM o)
SELECT COUNT(*) AS people_whose_first_order_ties FROM ranked WHERE rn = 1 AND same_ts > 1;

-- 10. Products whose category has no English name (the 2 categories behind the 13 orphan products).
SELECT p.product_category_name, COUNT(*) AS products
FROM ELIO_OLIST.RAW.PRODUCTS p LEFT JOIN ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL GROUP BY 1 ORDER BY 2 DESC;

-- 11. What does "revenue" mean? Compare the item-based and payment-based totals.
SELECT what, value FROM (
  SELECT 1 AS n, 'SUM(price) from order_items' AS what, ROUND(SUM(TRY_TO_NUMBER(price, 12, 2)), 2) AS value FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 2, 'SUM(freight_value) from order_items', ROUND(SUM(TRY_TO_NUMBER(freight_value, 12, 2)), 2) FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 3, 'SUM(price + freight_value) from order_items', ROUND(SUM(TRY_TO_NUMBER(price, 12, 2) + TRY_TO_NUMBER(freight_value, 12, 2)), 2) FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 4, 'SUM(payment_value) from order_payments', ROUND(SUM(TRY_TO_NUMBER(payment_value, 12, 2)), 2) FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL SELECT 5, 'orders where items total (price+freight) differs from payments total by more than 1.00', COUNT(*)
    FROM (SELECT i.order_id, SUM(TRY_TO_NUMBER(i.price, 12, 2) + TRY_TO_NUMBER(i.freight_value, 12, 2)) AS item_total FROM ELIO_OLIST.RAW.ORDER_ITEMS i GROUP BY 1) it
    JOIN (SELECT order_id, SUM(TRY_TO_NUMBER(payment_value, 12, 2)) AS pay_total FROM ELIO_OLIST.RAW.ORDER_PAYMENTS GROUP BY 1) pt ON pt.order_id = it.order_id
    WHERE ABS(it.item_total - pt.pay_total) > 1.00
  UNION ALL SELECT 6, 'orders present in both items and payments', COUNT(*)
    FROM (SELECT DISTINCT order_id FROM ELIO_OLIST.RAW.ORDER_ITEMS) i JOIN (SELECT DISTINCT order_id FROM ELIO_OLIST.RAW.ORDER_PAYMENTS) p ON p.order_id = i.order_id
) ORDER BY n;

-- 12. Timeline oddities among orders (counts of rows that break the expected order of events).
SELECT what, value FROM (
  SELECT 1 AS n, 'status delivered but no customer-delivery date' AS what, COUNT(*) AS value FROM ELIO_OLIST.RAW.ORDERS WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL
  UNION ALL SELECT 2, 'delivered to customer before it was purchased', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_delivered_customer_date < order_purchase_timestamp
  UNION ALL SELECT 3, 'delivered to customer before the carrier picked it up', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_delivered_customer_date < order_delivered_carrier_date
  UNION ALL SELECT 4, 'approved before it was purchased', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_approved_at < order_purchase_timestamp
  UNION ALL SELECT 5, 'estimated delivery date before the purchase date', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE TO_DATE(order_estimated_delivery_date) < TO_DATE(order_purchase_timestamp)
  UNION ALL SELECT 6, 'has a customer-delivery date but status is not delivered', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL
) ORDER BY n;

-- 13. Orders with several reviews: do the two newest tie on answer timestamp? (needs a tie-break)
WITH ranked AS (SELECT order_id, review_id, review_answer_timestamp AS ts,
                       ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) AS rn
                FROM ELIO_OLIST.RAW.ORDER_REVIEWS)
SELECT COUNT(*) AS orders_with_several_reviews, COUNT_IF(tie) AS where_the_two_newest_tie
FROM (SELECT a.order_id, (a.ts = b.ts) AS tie FROM ranked a JOIN ranked b ON a.order_id = b.order_id AND a.rn = 1 AND b.rn = 2);

-- 14. Date range of the orders (for the date dimension) and how "late" changes with the grain it is measured at.
SELECT MIN(order_purchase_timestamp) AS first_purchase, MAX(order_purchase_timestamp) AS last_purchase,
       MIN(order_estimated_delivery_date) AS first_estimate, MAX(order_estimated_delivery_date) AS last_estimate,
       MAX(order_delivered_customer_date) AS last_delivery
FROM ELIO_OLIST.RAW.ORDERS;
SELECT COUNT(*) AS delivered_orders_with_dates,
       COUNT_IF(TO_TIMESTAMP_NTZ(order_delivered_customer_date) > TO_TIMESTAMP_NTZ(order_estimated_delivery_date)) AS late_if_compared_as_timestamps,
       COUNT_IF(TO_DATE(order_delivered_customer_date) > TO_DATE(order_estimated_delivery_date)) AS late_if_compared_as_dates,
       ROUND(100 * COUNT_IF(TO_DATE(order_delivered_customer_date) > TO_DATE(order_estimated_delivery_date)) / COUNT(*), 2) AS pct_late_as_dates
FROM ELIO_OLIST.RAW.ORDERS WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;
-- 15. Does a zip prefix determine the city and state? (decides whether city/state can be split off the address in 3NF)
SELECT tbl, COUNT(*) AS zip_prefixes, COUNT_IF(cities > 1) AS with_more_than_1_city, COUNT_IF(states > 1) AS with_more_than_1_state FROM (
  SELECT 'customers' AS tbl, customer_zip_code_prefix AS z, COUNT(DISTINCT customer_city) AS cities, COUNT(DISTINCT customer_state) AS states
  FROM ELIO_OLIST.RAW.CUSTOMERS GROUP BY 1, 2
  UNION ALL
  SELECT 'sellers', seller_zip_code_prefix, COUNT(DISTINCT seller_city), COUNT(DISTINCT seller_state)
  FROM ELIO_OLIST.RAW.SELLERS GROUP BY 1, 2
) GROUP BY tbl ORDER BY tbl;

-- 16. Odd values worth flagging (kept as they are in RAW and staging, flagged in the data model doc).
SELECT what, value FROM (
  SELECT 1 AS n, 'payments with 0 installments' AS what, COUNT(*) AS value FROM ELIO_OLIST.RAW.ORDER_PAYMENTS WHERE TRY_TO_DECIMAL(payment_installments, 18, 4) = 0
  UNION ALL SELECT 2, 'payments of exactly 0.00', COUNT(*) FROM ELIO_OLIST.RAW.ORDER_PAYMENTS WHERE TRY_TO_NUMBER(payment_value, 12, 2) = 0
  UNION ALL SELECT 3, 'products weighing 0 g', COUNT(*) FROM ELIO_OLIST.RAW.PRODUCTS WHERE TRY_TO_DECIMAL(product_weight_g, 18, 4) = 0
  UNION ALL SELECT 4, 'items with freight of 0.00', COUNT(*) FROM ELIO_OLIST.RAW.ORDER_ITEMS WHERE TRY_TO_NUMBER(freight_value, 12, 2) = 0
) ORDER BY n;
-- 17. Item revenue by order status: do canceled / unavailable orders carry meaningful value? (decides what counts as revenue)
SELECT o.order_status, COUNT(DISTINCT o.order_id) AS orders_with_items, COUNT(*) AS items,
       ROUND(SUM(TRY_TO_NUMBER(i.price, 12, 2)), 2) AS price_total
FROM ELIO_OLIST.RAW.ORDERS o JOIN ELIO_OLIST.RAW.ORDER_ITEMS i ON i.order_id = o.order_id
GROUP BY 1 ORDER BY 4 DESC;
-- 18. Phase 5 design questions, answered before building the intermediate models and marts.
-- 18a. Orders by status for people's FIRST order: how many people's first order was canceled or unavailable?
--      (decides whether "first order" should skip non-revenue orders)
WITH o AS (SELECT c.customer_unique_id AS uid, o.order_status AS status, o.order_purchase_timestamp AS ts, o.order_id
           FROM ELIO_OLIST.RAW.ORDERS o JOIN ELIO_OLIST.RAW.CUSTOMERS c ON c.customer_id = o.customer_id),
ranked AS (SELECT uid, status, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ts, order_id) AS rn FROM o)
SELECT status AS first_order_status, COUNT(*) AS people FROM ranked WHERE rn = 1 GROUP BY 1 ORDER BY 2 DESC;

-- 18b. People with more than one order whose FIRST order was canceled or unavailable.
WITH o AS (SELECT c.customer_unique_id AS uid, o.order_status AS status, o.order_purchase_timestamp AS ts, o.order_id
           FROM ELIO_OLIST.RAW.ORDERS o JOIN ELIO_OLIST.RAW.CUSTOMERS c ON c.customer_id = o.customer_id),
ranked AS (SELECT uid, status, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY ts, order_id) AS rn, COUNT(*) OVER (PARTITION BY uid) AS n FROM o)
SELECT COUNT(*) AS repeat_people_whose_first_order_was_not_revenue FROM ranked WHERE rn = 1 AND n > 1 AND status IN ('canceled', 'unavailable');

-- 18c. Primary payment type = the payment with the largest value. Do the two largest payments of an order ever tie?
WITH ranked AS (SELECT order_id, TRY_TO_NUMBER(payment_value, 12, 2) AS v, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY TRY_TO_NUMBER(payment_value, 12, 2) DESC, TRY_TO_NUMBER(payment_sequential)) AS rn
                FROM ELIO_OLIST.RAW.ORDER_PAYMENTS)
SELECT COUNT(*) AS orders_where_the_two_largest_payments_tie
FROM ranked a JOIN ranked b ON a.order_id = b.order_id AND a.rn = 1 AND b.rn = 2 WHERE a.v = b.v;

-- 18d. Does any order mix payment types?  (how often "primary" matters)
SELECT COUNT(*) AS orders_with_more_than_one_payment_type
FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_PAYMENTS GROUP BY 1 HAVING COUNT(DISTINCT payment_type) > 1);

-- 18e. Sanity range of delivery times among delivered orders (calendar days, purchase date to delivery date).
SELECT MIN(d) AS min_days, MEDIAN(d) AS median_days, MAX(d) AS max_days, COUNT(*) AS orders FROM (
  SELECT DATEDIFF('day', TO_DATE(order_purchase_timestamp), TO_DATE(order_delivered_customer_date)) AS d
  FROM ELIO_OLIST.RAW.ORDERS WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL);