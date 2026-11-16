-- Plain-SQL check of the semantic layer (D73).

USE DATABASE ELIO_OLIST;

-- 1. orders and revenue. Revenue skips canceled and unavailable orders (D47): 13,494,400.74 over 99,441 orders.
SELECT
    COUNT(*)                                                   AS orders,
    SUM(revenue)                                               AS revenue,
    COUNT(*) = 99441 AND SUM(revenue) = 13494400.74            AS ok
FROM MARTS.FCT_ORDERS;

-- 2. average order value = revenue / revenue orders that have at least one item (D47): 137.42.
SELECT
    ROUND(SUM(revenue) / COUNT_IF(is_revenue_order AND item_count > 0), 2)           AS average_order_value,
    ROUND(SUM(revenue) / COUNT_IF(is_revenue_order AND item_count > 0), 2) = 137.42  AS ok
FROM MARTS.FCT_ORDERS;

-- 3. late delivery rate over measurable deliveries (D18, D19): 6,534 of 96,470, which is 6.77%.
SELECT
    COUNT_IF(is_late)                                                              AS late_orders,
    COUNT(is_late)                                                                 AS measurable_deliveries,
    ROUND(COUNT_IF(is_late) / COUNT(is_late), 4)                                   AS late_delivery_rate,
    COUNT_IF(is_late) = 6534 AND COUNT(is_late) = 96470
        AND ROUND(COUNT_IF(is_late) / COUNT(is_late), 4) = 0.0677                  AS ok
FROM MARTS.FCT_ORDERS;

-- 4. average review score, overall and split by late: 4.09 overall, 2.27 when late and 4.29 when on time.
SELECT
    ROUND(AVG(review_score), 2)                                AS average_review_score,
    ROUND(AVG(IFF(is_late, review_score, NULL)), 2)            AS when_late,
    ROUND(AVG(IFF(is_late = FALSE, review_score, NULL)), 2)    AS when_on_time,
    ROUND(AVG(review_score), 2) = 4.09
        AND ROUND(AVG(IFF(is_late, review_score, NULL)), 2) = 2.27
        AND ROUND(AVG(IFF(is_late = FALSE, review_score, NULL)), 2) = 4.29         AS ok
FROM MARTS.FCT_ORDERS;

-- 5. repeat rate after the first delivery (D46): 1,813 of the 93,248 people with a delivered first order, 1.94%.
SELECT
    COUNT_IF(repeat_after_first_delivery)                                          AS came_back,
    COUNT(repeat_after_first_delivery)                                             AS delivered_first_order,
    ROUND(COUNT_IF(repeat_after_first_delivery) / COUNT(repeat_after_first_delivery), 4)  AS repeat_rate,
    COUNT_IF(repeat_after_first_delivery) = 1813 AND COUNT(repeat_after_first_delivery) = 93248
        AND ROUND(COUNT_IF(repeat_after_first_delivery) / COUNT(repeat_after_first_delivery), 4) = 0.0194  AS ok
FROM MARTS.DIM_CUSTOMER;

-- 6. a metric sliced by a customer attribute: revenue by the state of the person's first order. SP (Sao Paulo) leads with 5,164,063.78.
SELECT c.first_order_state, SUM(o.revenue) AS revenue
FROM MARTS.FCT_ORDERS AS o
INNER JOIN MARTS.DIM_CUSTOMER AS c ON c.customer_sk = o.customer_sk
GROUP BY c.first_order_state
ORDER BY revenue DESC
LIMIT 3;
