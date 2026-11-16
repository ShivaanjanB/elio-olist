-- Sanity checks on the built star schema (ELIO_OLIST.MARTS).

USE DATABASE ELIO_OLIST;

-- 1. Row counts. Expect 99,441 / 112,650 / 96,096 / 32,951 / 3,095 / 1,096.
SELECT 'fct_orders' AS mart, COUNT(*) AS n FROM MARTS.FCT_ORDERS
UNION ALL SELECT 'fct_order_items', COUNT(*) FROM MARTS.FCT_ORDER_ITEMS
UNION ALL SELECT 'dim_customer', COUNT(*) FROM MARTS.DIM_CUSTOMER
UNION ALL SELECT 'dim_product', COUNT(*) FROM MARTS.DIM_PRODUCT
UNION ALL SELECT 'dim_seller', COUNT(*) FROM MARTS.DIM_SELLER
UNION ALL SELECT 'dim_date', COUNT(*) FROM MARTS.DIM_DATE;

-- 2. Revenue (D16, D17). Expect all items 13,591,643.70; excluded 97,242.96 (canceled 95,235.27 + unavailable 2,007.69);
--    revenue 13,494,400.74.
SELECT
    SUM(price)                                              AS all_item_price,
    SUM(IFF(is_revenue_order, 0, price))                    AS excluded_price,
    SUM(IFF(is_revenue_order, price, 0))                    AS revenue
FROM MARTS.FCT_ORDER_ITEMS;

-- 3. Revenue the other way round, from fct_orders. Must equal the revenue above.
SELECT SUM(items_price_total) AS revenue_from_orders, COUNT(*) AS revenue_orders
FROM MARTS.FCT_ORDERS WHERE is_revenue_order;

-- 4. Late delivery (D18, D19). Expect 96,470 measurable orders, 6,534 late, 6.77%.
SELECT
    COUNT(delivered_date)                                       AS measurable_orders,
    COUNT_IF(is_late)                                           AS late_orders,
    ROUND(100 * COUNT_IF(is_late) / COUNT(delivered_date), 2)   AS late_pct,
    COUNT_IF(is_late IS NULL)                                   AS not_measurable
FROM MARTS.FCT_ORDERS;

-- 5. Days to deliver (D19). Expect min 0, median 10, max 210, and a value only where delivered_date is set.
SELECT
    MIN(days_to_deliver) AS min_days, MEDIAN(days_to_deliver) AS median_days, MAX(days_to_deliver) AS max_days,
    COUNT(days_to_deliver) AS orders_with_days, COUNT(delivered_date) AS orders_with_delivered_date
FROM MARTS.FCT_ORDERS;

-- 6. People (D12, D13, D39). Expect 96,096 people, of whom 2,997 ordered more than once; 1,153 people whose first order
--    was canceled or unavailable, 55 of whom ordered again.
SELECT
    COUNT(*)                                                                AS people,
    COUNT_IF(d.has_multiple_orders)                                          AS repeat_people,
    COUNT_IF(NOT o.is_revenue_order)                                        AS first_order_not_revenue,
    COUNT_IF(NOT o.is_revenue_order AND d.has_multiple_orders)               AS not_revenue_and_repeat
FROM MARTS.DIM_CUSTOMER d
JOIN MARTS.FCT_ORDERS o ON o.order_id = d.first_order_id;

-- 7. Exactly one first order per person (checked per person, so one person with none and another with two cannot hide
--    behind matching totals). Expect 0 people that break the rule.
SELECT COUNT(*) AS people_without_exactly_one_first_order
FROM (
    SELECT customer_sk FROM MARTS.FCT_ORDERS
    GROUP BY customer_sk HAVING COUNT_IF(is_first_order) <> 1
);

-- 7b. "Came back" has two meanings (D46). Expect 2,997 people with more than one order, 93,248 with a delivered first
--     order, and 1,813 of those placing a later non-canceled order on or after the delivery day.
SELECT
    COUNT_IF(has_multiple_orders)                     AS has_multiple_orders,
    COUNT_IF(repeat_after_first_delivery IS NOT NULL) AS delivered_first_order,
    COUNT_IF(repeat_after_first_delivery)             AS returned_after_delivery
FROM MARTS.DIM_CUSTOMER;

-- 8. Orders missing a child (D14, D21). Expect 775 orders with no items, 768 with no review, 1 delivered order with no
--    payment; 547 orders with several reviews.
SELECT
    COUNT_IF(item_count = 0)                                          AS orders_without_items,
    COUNT_IF(review_count = 0)                                        AS orders_without_review,
    COUNT_IF(review_score IS NULL)                                    AS null_score,
    COUNT_IF(review_count > 1)                                        AS orders_with_several_reviews,
    COUNT_IF(payment_count = 0 AND order_status = 'delivered')        AS delivered_without_payment
FROM MARTS.FCT_ORDERS;

-- 9. Product categories (D22). Expect 610 'unknown' and 13 products still in Portuguese.
SELECT
    COUNT_IF(category_name = 'unknown')                                                    AS unknown_category,
    COUNT_IF(category_name IN ('portateis_cozinha_e_preparadores_de_alimentos', 'pc_gamer')) AS portuguese_fallback
FROM MARTS.DIM_PRODUCT;

-- 10. The star works end to end: top 10 categories by revenue with their share of the total. The shares come from one
--     join per dimension, and the revenue column must still add up to check 2.
SELECT
    p.category_name,
    ROUND(SUM(f.price), 2)                                               AS revenue,
    ROUND(100 * SUM(f.price) / SUM(SUM(f.price)) OVER (), 2)             AS share_pct
FROM MARTS.FCT_ORDER_ITEMS f
JOIN MARTS.DIM_PRODUCT p ON p.product_sk = f.product_sk
WHERE f.is_revenue_order
GROUP BY p.category_name
ORDER BY revenue DESC
LIMIT 10;

-- 11. Fan-out guard: joining the item fact to the order fact must not change the total price. Expect the same figure as
--     check 2, all item price.
SELECT SUM(f.price) AS price_through_the_join
FROM MARTS.FCT_ORDER_ITEMS f
JOIN MARTS.FCT_ORDERS o ON o.order_id = f.order_id;

-- 12. The calendar covers every purchase and estimate. Expect 2016-01-01 to 2018-12-31 and 0 facts outside it.
SELECT
    MIN(date_day) AS first_day, MAX(date_day) AS last_day,
    (SELECT COUNT(*) FROM MARTS.FCT_ORDERS o
      WHERE NOT EXISTS (SELECT 1 FROM MARTS.DIM_DATE d WHERE d.date_day = o.purchase_date)) AS orders_outside_calendar
FROM MARTS.DIM_DATE;

-- 13. The revenue columns do the filtering (D47). Expect 13,494,400.74 from both facts, and 13,591,643.70 for the
--     unfiltered price, so a plain SUM(revenue) cannot include canceled orders by mistake.
SELECT
    (SELECT SUM(revenue) FROM MARTS.FCT_ORDER_ITEMS)   AS revenue_items,
    (SELECT SUM(revenue) FROM MARTS.FCT_ORDERS)        AS revenue_orders,
    (SELECT SUM(price) FROM MARTS.FCT_ORDER_ITEMS)     AS price_unfiltered;

-- 14. A seller's late rate: by order, not by unit (D48). Overall expect 6,534 late of 96,470 orders (6.77%) by order and
--     7,264 of 110,189 items (6.59%) by unit, which is why units are the wrong thing to count.
SELECT
    COUNT(DISTINCT IFF(is_late IS NOT NULL, order_id, NULL))   AS measurable_orders,
    COUNT(DISTINCT IFF(is_late, order_id, NULL))               AS late_orders,
    COUNT_IF(is_late IS NOT NULL)                              AS measurable_units,
    COUNT_IF(is_late)                                          AS late_units
FROM MARTS.FCT_ORDER_ITEMS;

-- 15. Repeat after delivery by whether the first delivery was late (the Q5 shape).
SELECT o.is_late, COUNT(*) AS people,
       COUNT_IF(d.repeat_after_first_delivery) AS returned,
       ROUND(100 * COUNT_IF(d.repeat_after_first_delivery) / COUNT(*), 2) AS returned_pct
FROM MARTS.DIM_CUSTOMER d JOIN MARTS.FCT_ORDERS o ON o.order_id = d.first_order_id
WHERE d.repeat_after_first_delivery IS NOT NULL
GROUP BY o.is_late ORDER BY o.is_late;
