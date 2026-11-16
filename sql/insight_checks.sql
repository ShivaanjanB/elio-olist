-- Independent cross-checks for sql/insight_queries.sql (same method as sql/analytics_checks.sql, D55).

-- The order list rebuilt from staging: person, order number, delivered date, lateness and the latest review score.

-- C6. Insight 1: review score by lateness band, every band, mart against staging. Bands differing must be 0.
WITH latest_review AS (
    SELECT order_id, review_score
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_REVIEWS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) = 1
),

staged AS (
    SELECT
        CASE
            WHEN d <= -8 THEN 'early by 8+ days'
            WHEN d <= 0  THEN 'early by 0-7 days'
            WHEN d <= 3  THEN 'late 1-3 days'
            WHEN d <= 7  THEN 'late 4-7 days'
            WHEN d <= 14 THEN 'late 8-14 days'
            ELSE 'late 15+ days'
        END                  AS arrival,
        COUNT(*)             AS reviewed_orders,
        SUM(score)           AS score_sum
    FROM (
        SELECT
            DATEDIFF(day, CAST(o.order_estimated_delivery_date AS DATE), CAST(o.order_delivered_customer_date AS DATE)) AS d,
            r.review_score AS score
        FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
        INNER JOIN latest_review AS r ON r.order_id = o.order_id
        WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
    )
    GROUP BY 1
),

mart AS (
    SELECT
        CASE
            WHEN days_vs_estimate <= -8 THEN 'early by 8+ days'
            WHEN days_vs_estimate <= 0  THEN 'early by 0-7 days'
            WHEN days_vs_estimate <= 3  THEN 'late 1-3 days'
            WHEN days_vs_estimate <= 7  THEN 'late 4-7 days'
            WHEN days_vs_estimate <= 14 THEN 'late 8-14 days'
            ELSE 'late 15+ days'
        END                  AS arrival,
        COUNT(*)             AS reviewed_orders,
        SUM(review_score)    AS score_sum
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
    WHERE delivered_date IS NOT NULL AND review_score IS NOT NULL
    GROUP BY 1
)

SELECT
    'C6 lateness bands differing (orders or score total)'                                       AS check_name,
    COUNT_IF(m.reviewed_orders IS DISTINCT FROM s.reviewed_orders OR m.score_sum IS DISTINCT FROM s.score_sum) AS from_marts,
    0                                                                                            AS from_staging,
    COUNT_IF(m.reviewed_orders IS DISTINCT FROM s.reviewed_orders OR m.score_sum IS DISTINCT FROM s.score_sum) = 0 AS ok
FROM mart AS m
FULL OUTER JOIN staged AS s ON s.arrival = m.arrival
UNION ALL
SELECT 'C6 bands compared', COUNT(*), COUNT(*), TRUE FROM mart;


-- C7. Insight 2: people and returners at 56, 90 and 180 days, for the campaign segment and for all first-time buyers.
WITH params AS (
    SELECT MAX(CAST(order_purchase_timestamp AS DATE)) AS data_end
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS
),

latest_review AS (
    SELECT order_id, review_score
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_REVIEWS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) = 1
),

ranked AS (
    SELECT
        c.customer_unique_id,
        o.order_status,
        CAST(o.order_purchase_timestamp AS DATE)                                         AS purchase_date,
        IFF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL,
            CAST(o.order_delivered_customer_date AS DATE), NULL)                         AS delivered_date,
        CAST(o.order_estimated_delivery_date AS DATE)                                    AS estimated_date,
        r.review_score,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.order_purchase_timestamp, o.order_id)              AS order_number
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__CUSTOMERS AS c ON c.customer_id = o.customer_id
    LEFT JOIN latest_review AS r ON r.order_id = o.order_id
),

staged_cohort AS (
    SELECT
        f.customer_unique_id,
        f.delivered_date,
        (f.delivered_date > f.estimated_date OR f.review_score <= 2)                     AS in_segment
    FROM ranked AS f
    CROSS JOIN params AS p
    WHERE f.order_number = 1
      AND f.delivered_date IS NOT NULL
      AND DATEADD(day, 180, f.delivered_date) <= p.data_end
),

staged_return AS (
    SELECT
        c.customer_unique_id,
        MIN(DATEDIFF(day, c.delivered_date, l.purchase_date))                            AS d
    FROM staged_cohort AS c
    INNER JOIN ranked AS l ON l.customer_unique_id = c.customer_unique_id
    WHERE l.order_number > 1
      AND l.order_status NOT IN ('canceled', 'unavailable')
      AND l.purchase_date >= c.delivered_date
    GROUP BY c.customer_unique_id
),

staged AS (
    SELECT c.in_segment, r.d
    FROM staged_cohort AS c
    LEFT JOIN staged_return AS r ON r.customer_unique_id = c.customer_unique_id
),

mart_cohort AS (
    SELECT
        fo.customer_sk,
        fo.delivered_date,
        (fo.is_late OR fo.review_score <= 2)                                             AS in_segment
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, 180, fo.delivered_date) <= (SELECT MAX(purchase_date) FROM ELIO_OLIST.MARTS.FCT_ORDERS)
),

mart_return AS (
    SELECT
        c.customer_sk,
        MIN(DATEDIFF(day, c.delivered_date, l.purchase_date))                            AS d
    FROM mart_cohort AS c
    INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS l ON l.customer_sk = c.customer_sk
    WHERE NOT l.is_first_order
      AND l.is_revenue_order
      AND l.purchase_date >= c.delivered_date
    GROUP BY c.customer_sk
),

mart AS (
    SELECT c.in_segment, r.d
    FROM mart_cohort AS c
    LEFT JOIN mart_return AS r ON r.customer_sk = c.customer_sk
)

SELECT 'C7 first-time buyers in the cohort' AS check_name,
       (SELECT COUNT(*) FROM mart) AS from_marts, (SELECT COUNT(*) FROM staged) AS from_staging,
       (SELECT COUNT(*) FROM mart) = (SELECT COUNT(*) FROM staged) AS ok
UNION ALL
SELECT 'C7 campaign segment people',
       (SELECT COUNT_IF(COALESCE(in_segment, FALSE)) FROM mart), (SELECT COUNT_IF(COALESCE(in_segment, FALSE)) FROM staged),
       (SELECT COUNT_IF(COALESCE(in_segment, FALSE)) FROM mart) = (SELECT COUNT_IF(COALESCE(in_segment, FALSE)) FROM staged)
UNION ALL
SELECT 'C7 segment returners within 56 days',
       (SELECT COUNT_IF(in_segment AND d <= 56) FROM mart), (SELECT COUNT_IF(in_segment AND d <= 56) FROM staged),
       (SELECT COUNT_IF(in_segment AND d <= 56) FROM mart) = (SELECT COUNT_IF(in_segment AND d <= 56) FROM staged)
UNION ALL
SELECT 'C7 segment returners within 90 days',
       (SELECT COUNT_IF(in_segment AND d <= 90) FROM mart), (SELECT COUNT_IF(in_segment AND d <= 90) FROM staged),
       (SELECT COUNT_IF(in_segment AND d <= 90) FROM mart) = (SELECT COUNT_IF(in_segment AND d <= 90) FROM staged)
UNION ALL
SELECT 'C7 segment returners within 180 days',
       (SELECT COUNT_IF(in_segment AND d <= 180) FROM mart), (SELECT COUNT_IF(in_segment AND d <= 180) FROM staged),
       (SELECT COUNT_IF(in_segment AND d <= 180) FROM mart) = (SELECT COUNT_IF(in_segment AND d <= 180) FROM staged)
UNION ALL
SELECT 'C7 everyone else, returners within 180 days',
       (SELECT COUNT_IF(NOT COALESCE(in_segment, FALSE) AND d <= 180) FROM mart),
       (SELECT COUNT_IF(NOT COALESCE(in_segment, FALSE) AND d <= 180) FROM staged),
       (SELECT COUNT_IF(NOT COALESCE(in_segment, FALSE) AND d <= 180) FROM mart)
         = (SELECT COUNT_IF(NOT COALESCE(in_segment, FALSE) AND d <= 180) FROM staged);


-- C8. The sizing inputs (I3): the last 12 months of first deliveries, and what a later order is worth.
WITH latest_review AS (
    SELECT order_id, review_score
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_REVIEWS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) = 1
),

ranked AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_status,
        IFF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL,
            CAST(o.order_delivered_customer_date AS DATE), NULL)                         AS delivered_date,
        CAST(o.order_estimated_delivery_date AS DATE)                                    AS estimated_date,
        r.review_score,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.order_purchase_timestamp, o.order_id)              AS order_number
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__CUSTOMERS AS c ON c.customer_id = o.customer_id
    LEFT JOIN latest_review AS r ON r.order_id = o.order_id
),

item_totals AS (
    SELECT order_id, SUM(price) AS price, SUM(freight_value) AS freight
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_ITEMS
    GROUP BY order_id
),

staged_flow AS (
    SELECT
        COUNT(*)                                                                         AS first_time_buyers,
        COUNT_IF(delivered_date > estimated_date)                                        AS late,
        COUNT_IF(review_score <= 2)                                                      AS one_two_stars,
        COUNT_IF(delivered_date > estimated_date OR review_score <= 2)                   AS segment
    FROM ranked
    WHERE order_number = 1 AND delivered_date BETWEEN DATE '2017-09-01' AND DATE '2018-08-31'
),

mart_flow AS (
    SELECT
        COUNT(*)                                                                         AS first_time_buyers,
        COUNT_IF(is_late)                                                                AS late,
        COUNT_IF(review_score <= 2)                                                      AS one_two_stars,
        COUNT_IF(is_late OR review_score <= 2)                                           AS segment
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
    WHERE is_first_order AND delivered_date BETWEEN DATE '2017-09-01' AND DATE '2018-08-31'
),

staged_value AS (
    SELECT
        ROUND(AVG(it.price), 2)                                                          AS avg_price,
        ROUND(AVG(it.freight), 2)                                                        AS avg_freight,
        ROUND(AVG(LEAST(it.freight, 15)), 2)                                             AS avg_voucher_cost
    FROM ranked AS r
    INNER JOIN item_totals AS it ON it.order_id = r.order_id
    WHERE r.order_number > 1 AND r.order_status NOT IN ('canceled', 'unavailable')
),

mart_value AS (
    SELECT
        ROUND(AVG(items_price_total), 2)                                                 AS avg_price,
        ROUND(AVG(freight_total), 2)                                                     AS avg_freight,
        ROUND(AVG(LEAST(freight_total, 15)), 2)                                          AS avg_voucher_cost
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
    WHERE NOT is_first_order AND is_revenue_order AND item_count > 0
)

SELECT 'C8 first-time buyers per year' AS check_name, m.first_time_buyers AS from_marts, s.first_time_buyers AS from_staging,
       m.first_time_buyers = s.first_time_buyers AS ok FROM mart_flow AS m CROSS JOIN staged_flow AS s
UNION ALL
SELECT 'C8 first order late', m.late, s.late, m.late = s.late FROM mart_flow AS m CROSS JOIN staged_flow AS s
UNION ALL
SELECT 'C8 first order 1-2 stars', m.one_two_stars, s.one_two_stars, m.one_two_stars = s.one_two_stars FROM mart_flow AS m CROSS JOIN staged_flow AS s
UNION ALL
SELECT 'C8 campaign segment per year', m.segment, s.segment, m.segment = s.segment FROM mart_flow AS m CROSS JOIN staged_flow AS s
UNION ALL
SELECT 'C8 average item price on a later order', m.avg_price, s.avg_price, m.avg_price = s.avg_price FROM mart_value AS m CROSS JOIN staged_value AS s
UNION ALL
SELECT 'C8 average freight on a later order', m.avg_freight, s.avg_freight, m.avg_freight = s.avg_freight FROM mart_value AS m CROSS JOIN staged_value AS s
UNION ALL
SELECT 'C8 average voucher cost (capped at 15)', m.avg_voucher_cost, s.avg_voucher_cost, m.avg_voucher_cost = s.avg_voucher_cost FROM mart_value AS m CROSS JOIN staged_value AS s;
