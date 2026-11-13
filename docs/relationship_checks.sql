-- =============================================================================
-- docs/relationship_checks.sql
-- Evidence for the data model (docs/data_model.md): what one row means in each RAW table
-- (grain and keys), how the tables join, and how many child rows each parent has.
-- Read-only. Run as ELIO_TRANSFORMER:
--   .\.venv\Scripts\python.exe ingest\run_sql.py docs\relationship_checks.sql
-- =============================================================================

USE ROLE ELIO_TRANSFORMER;
USE WAREHOUSE ELIO_WH;
USE SCHEMA ELIO_OLIST.RAW;

-- 1. GRAIN AND KEYS: rows vs distinct key values. Equal = the key is unique (one row per key).
SELECT section, check_name, value FROM (
  SELECT 1 AS n, '1 keys' AS section, 'orders: rows' AS check_name, COUNT(*) AS value FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL SELECT 2, '1 keys', 'orders: distinct order_id', COUNT(DISTINCT order_id) FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL SELECT 3, '1 keys', 'customers: rows', COUNT(*) FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL SELECT 4, '1 keys', 'customers: distinct customer_id', COUNT(DISTINCT customer_id) FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL SELECT 5, '1 keys', 'customers: distinct customer_unique_id (people)', COUNT(DISTINCT customer_unique_id) FROM ELIO_OLIST.RAW.CUSTOMERS
  UNION ALL SELECT 6, '1 keys', 'order_items: rows', COUNT(*) FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 7, '1 keys', 'order_items: distinct (order_id, order_item_id)', COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id FROM ELIO_OLIST.RAW.ORDER_ITEMS)
  UNION ALL SELECT 8, '1 keys', 'order_payments: rows', COUNT(*) FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL SELECT 9, '1 keys', 'order_payments: distinct (order_id, payment_sequential)', COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential FROM ELIO_OLIST.RAW.ORDER_PAYMENTS)
  UNION ALL SELECT 10, '1 keys', 'order_reviews: rows', COUNT(*) FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL SELECT 11, '1 keys', 'order_reviews: distinct review_id', COUNT(DISTINCT review_id) FROM ELIO_OLIST.RAW.ORDER_REVIEWS
  UNION ALL SELECT 12, '1 keys', 'order_reviews: distinct (review_id, order_id)', COUNT(*) FROM (SELECT DISTINCT review_id, order_id FROM ELIO_OLIST.RAW.ORDER_REVIEWS)
  UNION ALL SELECT 13, '1 keys', 'products: rows', COUNT(*) FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL SELECT 14, '1 keys', 'products: distinct product_id', COUNT(DISTINCT product_id) FROM ELIO_OLIST.RAW.PRODUCTS
  UNION ALL SELECT 15, '1 keys', 'sellers: rows', COUNT(*) FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL SELECT 16, '1 keys', 'sellers: distinct seller_id', COUNT(DISTINCT seller_id) FROM ELIO_OLIST.RAW.SELLERS
  UNION ALL SELECT 17, '1 keys', 'category translation: rows', COUNT(*) FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
  UNION ALL SELECT 18, '1 keys', 'category translation: distinct product_category_name', COUNT(DISTINCT product_category_name) FROM ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION
) ORDER BY n;

-- 2. JOINS: orphans = child rows whose parent key has no match. 0 = every child has its parent.
SELECT section, check_name, value FROM (
  SELECT 1 AS n, '2 orphans' AS section, 'orders with no matching customer' AS check_name, COUNT(*) AS value
    FROM ELIO_OLIST.RAW.ORDERS o LEFT JOIN ELIO_OLIST.RAW.CUSTOMERS c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL
  UNION ALL SELECT 2, '2 orphans', 'order_items with no matching order', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS i LEFT JOIN ELIO_OLIST.RAW.ORDERS o ON i.order_id = o.order_id WHERE o.order_id IS NULL
  UNION ALL SELECT 3, '2 orphans', 'order_items with no matching product', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS i LEFT JOIN ELIO_OLIST.RAW.PRODUCTS p ON i.product_id = p.product_id WHERE p.product_id IS NULL
  UNION ALL SELECT 4, '2 orphans', 'order_items with no matching seller', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS i LEFT JOIN ELIO_OLIST.RAW.SELLERS s ON i.seller_id = s.seller_id WHERE s.seller_id IS NULL
  UNION ALL SELECT 5, '2 orphans', 'order_payments with no matching order', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_PAYMENTS p LEFT JOIN ELIO_OLIST.RAW.ORDERS o ON p.order_id = o.order_id WHERE o.order_id IS NULL
  UNION ALL SELECT 6, '2 orphans', 'order_reviews with no matching order', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_REVIEWS r LEFT JOIN ELIO_OLIST.RAW.ORDERS o ON r.order_id = o.order_id WHERE o.order_id IS NULL
  UNION ALL SELECT 7, '2 orphans', 'products whose category has no English translation (rows)', COUNT(*)
    FROM ELIO_OLIST.RAW.PRODUCTS p LEFT JOIN ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION t ON p.product_category_name = t.product_category_name
    WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
  UNION ALL SELECT 8, '2 orphans', 'categories used by products with no English translation (distinct)', COUNT(DISTINCT p.product_category_name)
    FROM ELIO_OLIST.RAW.PRODUCTS p LEFT JOIN ELIO_OLIST.RAW.PRODUCT_CATEGORY_NAME_TRANSLATION t ON p.product_category_name = t.product_category_name
    WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL
) ORDER BY n;

-- 3. FAN-OUT: how many child rows does one order have? More than 1 means a join to that child repeats the
--    order's row, which double-counts anything measured at order level (e.g. a payment total).
SELECT section, check_name, value FROM (
  SELECT 1 AS n, '3 fan-out' AS section, 'orders with no items' AS check_name, COUNT(*) AS value
    FROM ELIO_OLIST.RAW.ORDERS o WHERE NOT EXISTS (SELECT 1 FROM ELIO_OLIST.RAW.ORDER_ITEMS i WHERE i.order_id = o.order_id)
  UNION ALL SELECT 2, '3 fan-out', 'orders with more than 1 item', COUNT(*)
    FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_ITEMS GROUP BY 1 HAVING COUNT(*) > 1)
  UNION ALL SELECT 3, '3 fan-out', 'most items on one order', MAX(c) FROM (SELECT COUNT(*) AS c FROM ELIO_OLIST.RAW.ORDER_ITEMS GROUP BY order_id)
  UNION ALL SELECT 4, '3 fan-out', 'orders with items from more than 1 seller', COUNT(*)
    FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_ITEMS GROUP BY 1 HAVING COUNT(DISTINCT seller_id) > 1)
  UNION ALL SELECT 5, '3 fan-out', 'orders with no payment', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDERS o WHERE NOT EXISTS (SELECT 1 FROM ELIO_OLIST.RAW.ORDER_PAYMENTS p WHERE p.order_id = o.order_id)
  UNION ALL SELECT 6, '3 fan-out', 'orders with more than 1 payment', COUNT(*)
    FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_PAYMENTS GROUP BY 1 HAVING COUNT(*) > 1)
  UNION ALL SELECT 7, '3 fan-out', 'most payments on one order', MAX(c) FROM (SELECT COUNT(*) AS c FROM ELIO_OLIST.RAW.ORDER_PAYMENTS GROUP BY order_id)
  UNION ALL SELECT 8, '3 fan-out', 'orders with no review', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDERS o WHERE NOT EXISTS (SELECT 1 FROM ELIO_OLIST.RAW.ORDER_REVIEWS r WHERE r.order_id = o.order_id)
  UNION ALL SELECT 9, '3 fan-out', 'orders with more than 1 review', COUNT(*)
    FROM (SELECT order_id FROM ELIO_OLIST.RAW.ORDER_REVIEWS GROUP BY 1 HAVING COUNT(*) > 1)
  UNION ALL SELECT 10, '3 fan-out', 'most customer_id values for one person (customer_unique_id)', MAX(c)
    FROM (SELECT COUNT(DISTINCT customer_id) AS c FROM ELIO_OLIST.RAW.CUSTOMERS GROUP BY customer_unique_id)
  UNION ALL SELECT 11, '3 fan-out', 'orders per customer_id (most)', MAX(c) FROM (SELECT COUNT(*) AS c FROM ELIO_OLIST.RAW.ORDERS GROUP BY customer_id)
) ORDER BY n;

-- 4. FAN-OUT DEMO: why every number must be summed at the grain it was recorded at.
--    price lives on order_items (one row per item); payment_value lives on order_payments (one row per
--    payment). Joining the two through order_id repeats each item once per payment of its order.
SELECT what, value FROM (
  SELECT 1 AS n, 'rows in order_items' AS what, COUNT(*)::NUMBER(14,2) AS value FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 2, 'rows after joining order_items to order_payments on order_id (inflated)', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS i JOIN ELIO_OLIST.RAW.ORDER_PAYMENTS p ON p.order_id = i.order_id
  UNION ALL SELECT 3, 'SUM(price) straight from order_items (correct)', ROUND(SUM(TRY_TO_NUMBER(price, 12, 2)), 2)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS
  UNION ALL SELECT 4, 'SUM(price) after joining to order_payments (inflated)', ROUND(SUM(TRY_TO_NUMBER(i.price, 12, 2)), 2)
    FROM ELIO_OLIST.RAW.ORDER_ITEMS i JOIN ELIO_OLIST.RAW.ORDER_PAYMENTS p ON p.order_id = i.order_id
  UNION ALL SELECT 5, 'SUM(payment_value) straight from order_payments (correct)', ROUND(SUM(TRY_TO_NUMBER(payment_value, 12, 2)), 2)
    FROM ELIO_OLIST.RAW.ORDER_PAYMENTS
  UNION ALL SELECT 6, 'SUM(payment_value) after joining to order_items (inflated)', ROUND(SUM(TRY_TO_NUMBER(p.payment_value, 12, 2)), 2)
    FROM ELIO_OLIST.RAW.ORDER_PAYMENTS p JOIN ELIO_OLIST.RAW.ORDER_ITEMS i ON i.order_id = p.order_id
  UNION ALL SELECT 7, 'rows in orders', COUNT(*) FROM ELIO_OLIST.RAW.ORDERS
  UNION ALL SELECT 8, 'rows after joining orders to order_reviews', COUNT(*)
    FROM ELIO_OLIST.RAW.ORDERS o JOIN ELIO_OLIST.RAW.ORDER_REVIEWS r ON r.order_id = o.order_id
) ORDER BY n;