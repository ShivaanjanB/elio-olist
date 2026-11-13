-- Independent cross-checks for sql/analytics_queries.sql.
--
-- Each check recomputes a figure from the STAGING views, by a different route from the marts (staging timestamps and
-- natural keys instead of the facts' dates and surrogate keys), and compares it with the same figure taken from the marts.
-- The tests in dbt prove the marts agree with staging in total; these prove the specific numbers the analysis uses.
--
--   . .\scripts\load_env.ps1
--   .\.venv\Scripts\python.exe ingest\run_sql.py sql\analytics_checks.sql
--
-- Every check returns rows of: check_name, from_marts, from_staging, ok. Every ok must be TRUE.


-- C1. Revenue by category (Q1): every category, mart against staging. mismatches must be 0.
WITH mart AS (
    SELECT dp.category_name, ROUND(SUM(fi.revenue), 2) AS revenue
    FROM ELIO_OLIST.MARTS.FCT_ORDER_ITEMS AS fi
    INNER JOIN ELIO_OLIST.MARTS.DIM_PRODUCT AS dp ON dp.product_sk = fi.product_sk
    WHERE fi.is_revenue_order
    GROUP BY dp.category_name
),

staged AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category_name,
        ROUND(SUM(i.price), 2)                                                        AS revenue
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_ITEMS AS i
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
        ON o.order_id = i.order_id AND o.order_status NOT IN ('canceled', 'unavailable')
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__PRODUCTS AS p ON p.product_id = i.product_id
    LEFT JOIN ELIO_OLIST.STAGING.STG_OLIST__PRODUCT_CATEGORY_TRANSLATION AS t
        ON t.product_category_name = p.product_category_name
    GROUP BY 1
)

SELECT
    'C1 revenue by category: categories differing'                       AS check_name,
    COUNT_IF(m.revenue IS DISTINCT FROM s.revenue)                       AS from_marts,
    0                                                                    AS from_staging,
    COUNT_IF(m.revenue IS DISTINCT FROM s.revenue) = 0                   AS ok
FROM mart AS m
FULL OUTER JOIN staged AS s ON s.category_name = m.category_name
UNION ALL
SELECT
    'C1 total revenue',
    (SELECT SUM(revenue) FROM mart),
    (SELECT SUM(revenue) FROM staged),
    (SELECT SUM(revenue) FROM mart) = (SELECT SUM(revenue) FROM staged);


-- C2. Monthly orders and revenue (Q2): every month, mart against staging. Months differing must be 0.
WITH mart AS (
    SELECT dd.year_month, COUNT(*) AS orders, ROUND(SUM(fo.revenue), 2) AS revenue
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    INNER JOIN ELIO_OLIST.MARTS.DIM_DATE AS dd ON dd.date_day = fo.purchase_date
    WHERE fo.is_revenue_order AND fo.item_count > 0
    GROUP BY dd.year_month
),

staged AS (
    SELECT
        TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM') AS year_month,
        COUNT(*)                                        AS orders,
        ROUND(SUM(it.items_price), 2)                   AS revenue
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
    INNER JOIN (
        SELECT order_id, SUM(price) AS items_price
        FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_ITEMS
        GROUP BY order_id
    ) AS it ON it.order_id = o.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
)

SELECT
    'C2 months differing (orders or revenue)'                                                        AS check_name,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders OR m.revenue IS DISTINCT FROM s.revenue)             AS from_marts,
    0                                                                                                AS from_staging,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders OR m.revenue IS DISTINCT FROM s.revenue) = 0         AS ok
FROM mart AS m
FULL OUTER JOIN staged AS s ON s.year_month = m.year_month
UNION ALL
SELECT
    'C2 months compared',
    COUNT(*),
    COUNT(*),
    TRUE
FROM mart;


-- C3. Seller late rates and the delivery-time cut (Q3).
WITH mart_sellers AS (
    SELECT ds.seller_id, COUNT(*) AS orders, SUM(so.is_late) AS late_orders
    FROM (
        SELECT fi.seller_sk, fi.order_id, MAX(IFF(fi.is_late, 1, 0)) AS is_late
        FROM ELIO_OLIST.MARTS.FCT_ORDER_ITEMS AS fi
        WHERE fi.is_late IS NOT NULL
        GROUP BY fi.seller_sk, fi.order_id
    ) AS so
    INNER JOIN ELIO_OLIST.MARTS.DIM_SELLER AS ds ON ds.seller_sk = so.seller_sk
    GROUP BY ds.seller_id
),

staged_sellers AS (
    SELECT
        i.seller_id,
        COUNT(DISTINCT i.order_id)                                                                  AS orders,
        COUNT(DISTINCT IFF(CAST(o.order_delivered_customer_date AS DATE)
                           > CAST(o.order_estimated_delivery_date AS DATE), i.order_id, NULL))      AS late_orders
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_ITEMS AS i
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY i.seller_id
)

SELECT
    'C3 sellers differing (orders or late orders)'                                                   AS check_name,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders OR m.late_orders IS DISTINCT FROM s.late_orders)     AS from_marts,
    0                                                                                                AS from_staging,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders OR m.late_orders IS DISTINCT FROM s.late_orders) = 0 AS ok
FROM mart_sellers AS m
FULL OUTER JOIN staged_sellers AS s ON s.seller_id = m.seller_id;


WITH mart AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days_to_deliver) AS p99,
        COUNT_IF(days_to_deliver > (SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days_to_deliver)
                                    FROM ELIO_OLIST.MARTS.FCT_ORDERS))            AS above_p99
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
),

staged_days AS (
    SELECT DATEDIFF(day, CAST(order_purchase_timestamp AS DATE), CAST(order_delivered_customer_date AS DATE)) AS days
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS
    WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
),

staged AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days)                                         AS p99,
        COUNT_IF(days > (SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days) FROM staged_days)) AS above_p99
    FROM staged_days
)

SELECT 'C3 p99 delivery days' AS check_name, m.p99 AS from_marts, s.p99 AS from_staging, m.p99 = s.p99 AS ok
FROM mart AS m CROSS JOIN staged AS s
UNION ALL
SELECT 'C3 orders above p99', m.above_p99, s.above_p99, m.above_p99 = s.above_p99
FROM mart AS m CROSS JOIN staged AS s;


-- C4. State breakdown (Q4): sums and counts per state, mart against staging. States differing must be 0.
WITH mart AS (
    SELECT
        fo.customer_state                                       AS state,
        COUNT(*)                                                AS orders,
        COUNT(fo.delivered_date)                                AS delivered_orders,
        COUNT_IF(fo.is_late)                                    AS late_orders,
        SUM(fo.days_to_deliver)                                 AS days_sum,
        SUM(fo.review_score)                                    AS review_sum,
        COUNT(fo.review_score)                                  AS reviewed_orders,
        ROUND(SUM(fo.revenue), 2)                               AS revenue,
        ROUND(SUM(IFF(fo.is_revenue_order, fo.freight_total, 0)), 2) AS freight
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    GROUP BY fo.customer_state
),

latest_review AS (
    SELECT order_id, review_score
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_REVIEWS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) = 1
),

item_totals AS (
    SELECT order_id, SUM(price) AS price, SUM(freight_value) AS freight
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDER_ITEMS
    GROUP BY order_id
),

staged AS (
    SELECT
        c.customer_state                                                                             AS state,
        COUNT(*)                                                                                     AS orders,
        COUNT_IF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL)       AS delivered_orders,
        COUNT_IF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
                 AND CAST(o.order_delivered_customer_date AS DATE) > CAST(o.order_estimated_delivery_date AS DATE)) AS late_orders,
        SUM(IFF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL,
                DATEDIFF(day, CAST(o.order_purchase_timestamp AS DATE), CAST(o.order_delivered_customer_date AS DATE)), NULL)) AS days_sum,
        SUM(r.review_score)                                                                          AS review_sum,
        COUNT(r.review_score)                                                                        AS reviewed_orders,
        ROUND(SUM(IFF(o.order_status NOT IN ('canceled', 'unavailable'), COALESCE(it.price, 0), 0)), 2)   AS revenue,
        ROUND(SUM(IFF(o.order_status NOT IN ('canceled', 'unavailable'), COALESCE(it.freight, 0), 0)), 2) AS freight
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__CUSTOMERS AS c ON c.customer_id = o.customer_id
    LEFT JOIN latest_review AS r ON r.order_id = o.order_id
    LEFT JOIN item_totals AS it ON it.order_id = o.order_id
    GROUP BY c.customer_state
)

SELECT
    'C4 states differing (any of 8 measures)'                                              AS check_name,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders
          OR m.delivered_orders IS DISTINCT FROM s.delivered_orders
          OR m.late_orders IS DISTINCT FROM s.late_orders
          OR m.days_sum IS DISTINCT FROM s.days_sum
          OR m.review_sum IS DISTINCT FROM s.review_sum
          OR m.reviewed_orders IS DISTINCT FROM s.reviewed_orders
          OR m.revenue IS DISTINCT FROM s.revenue
          OR m.freight IS DISTINCT FROM s.freight)                                         AS from_marts,
    0                                                                                      AS from_staging,
    COUNT_IF(m.orders IS DISTINCT FROM s.orders
          OR m.delivered_orders IS DISTINCT FROM s.delivered_orders
          OR m.late_orders IS DISTINCT FROM s.late_orders
          OR m.days_sum IS DISTINCT FROM s.days_sum
          OR m.review_sum IS DISTINCT FROM s.review_sum
          OR m.reviewed_orders IS DISTINCT FROM s.reviewed_orders
          OR m.revenue IS DISTINCT FROM s.revenue
          OR m.freight IS DISTINCT FROM s.freight) = 0                                     AS ok
FROM mart AS m
FULL OUTER JOIN staged AS s ON s.state = m.state;


-- C5. Repeat rate by first-order experience (Q5): the cohort and its returners, rebuilt from staging timestamps.
WITH params AS (
    SELECT 180 AS follow_up_days, MAX(CAST(order_purchase_timestamp AS DATE)) AS data_end
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS
),

ranked AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_status,
        CAST(o.order_purchase_timestamp AS DATE)                                               AS purchase_date,
        IFF(o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL,
            CAST(o.order_delivered_customer_date AS DATE), NULL)                               AS delivered_date,
        CAST(o.order_estimated_delivery_date AS DATE)                                          AS estimated_date,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.order_purchase_timestamp, o.order_id)                    AS order_number
    FROM ELIO_OLIST.STAGING.STG_OLIST__ORDERS AS o
    INNER JOIN ELIO_OLIST.STAGING.STG_OLIST__CUSTOMERS AS c ON c.customer_id = o.customer_id
),

staged_cohort AS (
    SELECT
        f.customer_unique_id,
        f.delivered_date > f.estimated_date                                                    AS late,
        EXISTS (
            SELECT 1 FROM ranked AS later
            WHERE later.customer_unique_id = f.customer_unique_id
              AND later.order_number > 1
              AND later.order_status NOT IN ('canceled', 'unavailable')
              AND later.purchase_date >= f.delivered_date
              AND later.purchase_date <= DATEADD(day, p.follow_up_days, f.delivered_date)
        )                                                                                      AS returned
    FROM ranked AS f
    CROSS JOIN params AS p
    WHERE f.order_number = 1
      AND f.delivered_date IS NOT NULL
      AND DATEADD(day, p.follow_up_days, f.delivered_date) <= p.data_end
),

mart_cohort AS (
    SELECT
        fo.customer_sk,
        fo.is_late                                                                             AS late,
        EXISTS (
            SELECT 1 FROM ELIO_OLIST.MARTS.FCT_ORDERS AS later
            WHERE later.customer_sk = fo.customer_sk
              AND NOT later.is_first_order
              AND later.is_revenue_order
              AND later.purchase_date >= fo.delivered_date
              AND later.purchase_date <= DATEADD(day, 180, fo.delivered_date)
        )                                                                                      AS returned
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, 180, fo.delivered_date) <= (SELECT MAX(purchase_date) FROM ELIO_OLIST.MARTS.FCT_ORDERS)
)

SELECT 'C5 cohort size (people with a delivered first order and 180 days of follow-up)' AS check_name,
       (SELECT COUNT(*) FROM mart_cohort) AS from_marts, (SELECT COUNT(*) FROM staged_cohort) AS from_staging,
       (SELECT COUNT(*) FROM mart_cohort) = (SELECT COUNT(*) FROM staged_cohort) AS ok
UNION ALL
SELECT 'C5 returners',
       (SELECT COUNT_IF(returned) FROM mart_cohort), (SELECT COUNT_IF(returned) FROM staged_cohort),
       (SELECT COUNT_IF(returned) FROM mart_cohort) = (SELECT COUNT_IF(returned) FROM staged_cohort)
UNION ALL
SELECT 'C5 on-time people',
       (SELECT COUNT_IF(NOT late) FROM mart_cohort), (SELECT COUNT_IF(NOT late) FROM staged_cohort),
       (SELECT COUNT_IF(NOT late) FROM mart_cohort) = (SELECT COUNT_IF(NOT late) FROM staged_cohort)
UNION ALL
SELECT 'C5 on-time returners',
       (SELECT COUNT_IF(NOT late AND returned) FROM mart_cohort), (SELECT COUNT_IF(NOT late AND returned) FROM staged_cohort),
       (SELECT COUNT_IF(NOT late AND returned) FROM mart_cohort) = (SELECT COUNT_IF(NOT late AND returned) FROM staged_cohort)
UNION ALL
SELECT 'C5 late people',
       (SELECT COUNT_IF(late) FROM mart_cohort), (SELECT COUNT_IF(late) FROM staged_cohort),
       (SELECT COUNT_IF(late) FROM mart_cohort) = (SELECT COUNT_IF(late) FROM staged_cohort)
UNION ALL
SELECT 'C5 late returners',
       (SELECT COUNT_IF(late AND returned) FROM mart_cohort), (SELECT COUNT_IF(late AND returned) FROM staged_cohort),
       (SELECT COUNT_IF(late AND returned) FROM mart_cohort) = (SELECT COUNT_IF(late AND returned) FROM staged_cohort);
