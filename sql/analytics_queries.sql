-- Analytics queries (brief A5): five questions answered from the star schema in ELIO_OLIST.MARTS.


-- Q1. Top 10 product categories by revenue, with each one's share of total revenue.
WITH category_revenue AS (
    SELECT
        dp.category_name,
        SUM(fi.revenue)             AS revenue,
        COUNT(DISTINCT fi.order_id) AS orders,
        COUNT(*)                    AS units
    FROM ELIO_OLIST.MARTS.FCT_ORDER_ITEMS AS fi
    INNER JOIN ELIO_OLIST.MARTS.DIM_PRODUCT AS dp
        ON dp.product_sk = fi.product_sk
    WHERE fi.is_revenue_order            -- keeps canceled orders out of the order and unit counts as well as the money
    GROUP BY dp.category_name
),

ranked AS (
    SELECT
        category_name,
        revenue,
        orders,
        units,
        RANK() OVER (ORDER BY revenue DESC)              AS revenue_rank,
        revenue / NULLIF(SUM(revenue) OVER (), 0)        AS share_of_total
    FROM category_revenue
)

SELECT
    revenue_rank,
    category_name,
    ROUND(revenue, 2)                                         AS revenue,
    ROUND(100 * share_of_total, 2)                            AS share_pct,
    ROUND(100 * SUM(share_of_total) OVER (ORDER BY revenue_rank), 2) AS cumulative_share_pct,
    orders,
    units
FROM ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank;


-- Q2. Monthly orders, revenue and average order value, with month-on-month change.
WITH monthly AS (
    SELECT
        dd.year_month,
        COUNT(*)           AS orders,
        SUM(fo.revenue)    AS revenue
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    INNER JOIN ELIO_OLIST.MARTS.DIM_DATE AS dd
        ON dd.date_day = fo.purchase_date
    WHERE fo.is_revenue_order
      AND fo.item_count > 0
      AND dd.year_month BETWEEN '2017-01' AND '2018-08'     -- the trimmed window (D51); year_month sorts as text
    GROUP BY dd.year_month
)

SELECT
    year_month,
    orders,
    ROUND(revenue, 2)                                                            AS revenue,
    ROUND(revenue / NULLIF(orders, 0), 2)                                        AS avg_order_value,
    ROUND(100 * (orders  / NULLIF(LAG(orders)  OVER (ORDER BY year_month), 0) - 1), 1)   AS orders_mom_pct,
    ROUND(100 * (revenue / NULLIF(LAG(revenue) OVER (ORDER BY year_month), 0) - 1), 1)   AS revenue_mom_pct,
    ROUND(100 * ((revenue / NULLIF(orders, 0))
               / NULLIF(LAG(revenue / NULLIF(orders, 0)) OVER (ORDER BY year_month), 0) - 1), 1) AS aov_mom_pct
FROM monthly
ORDER BY year_month;


-- Q2b. The months that were left out, so the trimming is visible and checkable.
SELECT
    dd.year_month,
    COUNT(*)                                          AS all_orders,
    COUNT_IF(fo.is_revenue_order AND fo.item_count > 0) AS revenue_orders,
    ROUND(SUM(fo.revenue), 2)                         AS revenue
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
INNER JOIN ELIO_OLIST.MARTS.DIM_DATE AS dd
    ON dd.date_day = fo.purchase_date
WHERE dd.year_month NOT BETWEEN '2017-01' AND '2018-08'
GROUP BY dd.year_month
ORDER BY dd.year_month;


-- Q3a. Anomaly: sellers whose late rate is unusually high (z-score above 2).
WITH params AS (
    SELECT
        30 AS min_orders,
        2  AS z_cutoff,
        (SELECT COUNT_IF(is_late) / COUNT(is_late) FROM ELIO_OLIST.MARTS.FCT_ORDERS) AS platform_late_rate
),

seller_orders AS (
    -- one row per seller and order, so a multi-item order counts once for its seller
    SELECT
        fi.seller_sk,
        fi.order_id,
        MAX(IFF(fi.is_late, 1, 0)) AS is_late
    FROM ELIO_OLIST.MARTS.FCT_ORDER_ITEMS AS fi
    WHERE fi.is_late IS NOT NULL         -- only orders whose delivery can be measured
    GROUP BY fi.seller_sk, fi.order_id
),

seller_rates AS (
    SELECT
        so.seller_sk,
        COUNT(*)                    AS orders,
        SUM(so.is_late)             AS late_orders,
        SUM(so.is_late) / COUNT(*)  AS late_rate
    FROM seller_orders AS so
    GROUP BY so.seller_sk
    HAVING COUNT(*) >= (SELECT min_orders FROM params)
),

scored AS (
    SELECT
        sr.seller_sk,
        sr.orders,
        sr.late_orders,
        sr.late_rate,
        (sr.late_rate - AVG(sr.late_rate) OVER ()) / NULLIF(STDDEV(sr.late_rate) OVER (), 0) AS z_across_sellers,
        (sr.late_rate - p.platform_late_rate)
            / SQRT(p.platform_late_rate * (1 - p.platform_late_rate) / sr.orders)             AS z_vs_platform_rate
    FROM seller_rates AS sr
    CROSS JOIN params AS p
)

SELECT
    ds.seller_id,
    ds.state,
    ds.city,
    sc.orders,
    sc.late_orders,
    ROUND(100 * sc.late_rate, 1)        AS late_rate_pct,
    ROUND(sc.z_across_sellers, 2)       AS z_across_sellers,
    ROUND(sc.z_vs_platform_rate, 2)     AS z_vs_platform_rate,
    sc.z_vs_platform_rate > p.z_cutoff  AS high_against_platform_too
FROM scored AS sc
INNER JOIN ELIO_OLIST.MARTS.DIM_SELLER AS ds
    ON ds.seller_sk = sc.seller_sk
CROSS JOIN params AS p
WHERE sc.z_across_sellers > p.z_cutoff
ORDER BY sc.z_across_sellers DESC
LIMIT 50;


-- Q3a-summary. How big is the seller problem? Same scoring as above, rolled up.
WITH params AS (
    SELECT 30 AS min_orders, 2 AS z_cutoff
),

seller_orders AS (
    SELECT fi.seller_sk, fi.order_id, MAX(IFF(fi.is_late, 1, 0)) AS is_late
    FROM ELIO_OLIST.MARTS.FCT_ORDER_ITEMS AS fi
    WHERE fi.is_late IS NOT NULL
    GROUP BY fi.seller_sk, fi.order_id
),

seller_rates AS (
    SELECT so.seller_sk, COUNT(*) AS orders, SUM(so.is_late) AS late_orders, SUM(so.is_late) / COUNT(*) AS late_rate
    FROM seller_orders AS so
    GROUP BY so.seller_sk
    HAVING COUNT(*) >= (SELECT min_orders FROM params)
),

scored AS (
    SELECT
        sr.*,
        (sr.late_rate - AVG(sr.late_rate) OVER ()) / NULLIF(STDDEV(sr.late_rate) OVER (), 0) AS z_across_sellers
    FROM seller_rates AS sr
)

SELECT
    COUNT(*)                                                    AS scored_sellers,
    ROUND(100 * AVG(late_rate), 2)                              AS avg_seller_late_rate_pct,
    ROUND(100 * STDDEV(late_rate), 2)                           AS stddev_pct_points,
    COUNT_IF(z_across_sellers > (SELECT z_cutoff FROM params))  AS flagged_sellers,
    SUM(IFF(z_across_sellers > (SELECT z_cutoff FROM params), late_orders, 0))  AS late_orders_of_flagged,
    SUM(late_orders)                                            AS late_orders_of_scored,
    ROUND(100 * SUM(IFF(z_across_sellers > (SELECT z_cutoff FROM params), late_orders, 0)) / NULLIF(SUM(late_orders), 0), 1)
                                                                AS flagged_share_of_scored_late_orders_pct
FROM scored;


-- Q3b. Anomaly: orders slower than the 99th percentile of delivery time (listing, slowest first).
WITH cut AS (
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days_to_deliver) AS p99_days
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
)

SELECT
    fo.order_id,
    fo.customer_state,
    fo.purchase_date,
    fo.delivered_date,
    fo.days_to_deliver,
    fo.days_vs_estimate,
    fo.review_score,
    cut.p99_days
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
CROSS JOIN cut
WHERE fo.days_to_deliver > cut.p99_days
ORDER BY fo.days_to_deliver DESC, fo.order_id
LIMIT 25;


-- Q3c. What the extreme orders look like next to every other delivered order.
WITH cut AS (
    SELECT PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY days_to_deliver) AS p99_days
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
)

SELECT
    IFF(fo.days_to_deliver > cut.p99_days, 'above p99', 'p99 or faster')            AS delivery_group,
    COUNT(*)                                                                         AS orders,
    ROUND(AVG(fo.days_to_deliver), 1)                                                AS avg_days_to_deliver,
    ROUND(100 * COUNT_IF(fo.is_late) / NULLIF(COUNT(fo.is_late), 0), 1)              AS late_pct,
    ROUND(AVG(fo.review_score), 2)                                                   AS avg_review_score,
    ROUND(100 * COUNT_IF(fo.review_score = 1) / NULLIF(COUNT(fo.review_score), 0), 1) AS one_star_pct
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
CROSS JOIN cut
WHERE fo.days_to_deliver IS NOT NULL
GROUP BY IFF(fo.days_to_deliver > cut.p99_days, 'above p99', 'p99 or faster')
ORDER BY delivery_group;


-- Q4. Breakdown by customer state: delivery days, late %, average review and freight ratio.
SELECT
    fo.customer_state,
    COUNT(*)                                                                        AS orders,
    COUNT(fo.delivered_date)                                                        AS delivered_orders,
    ROUND(AVG(fo.days_to_deliver), 1)                                               AS avg_days_to_deliver,
    ROUND(100 * COUNT_IF(fo.is_late) / NULLIF(COUNT(fo.is_late), 0), 2)             AS late_pct,
    ROUND(AVG(fo.review_score), 2)                                                  AS avg_review_score,
    ROUND(SUM(IFF(fo.is_revenue_order, fo.freight_total, 0))
          / NULLIF(SUM(fo.revenue), 0), 3)                                          AS freight_ratio,
    ROUND(SUM(fo.revenue), 2)                                                       AS revenue,
    COUNT(fo.delivered_date) >= 100                                                 AS enough_data
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
GROUP BY fo.customer_state
ORDER BY late_pct DESC, fo.customer_state;


-- Q5. The stakeholder question: how does the repeat rate depend on the first order's delivery experience?
WITH params AS (
    SELECT 180 AS follow_up_days, MAX(purchase_date) AS data_end
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
),

first_orders AS (
    SELECT
        fo.customer_sk,
        fo.delivered_date,
        fo.days_vs_estimate,
        fo.review_score
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    CROSS JOIN params AS p
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, p.follow_up_days, fo.delivered_date) <= p.data_end    -- a full follow-up window exists
),

returners AS (
    SELECT DISTINCT fi.customer_sk
    FROM first_orders AS fi
    INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS later
        ON later.customer_sk = fi.customer_sk
    CROSS JOIN params AS p
    WHERE NOT later.is_first_order
      AND later.is_revenue_order                                  -- a canceled follow-up is not a return
      AND later.purchase_date >= fi.delivered_date
      AND later.purchase_date <= DATEADD(day, p.follow_up_days, fi.delivered_date)
),

cohort AS (
    SELECT
        fi.customer_sk,
        CASE
            WHEN fi.days_vs_estimate <= 0 THEN 'on time or early'
            WHEN fi.days_vs_estimate <= 7 THEN 'late 1-7 days'
            ELSE 'late 8+ days'
        END                                                  AS timeliness,
        CASE
            WHEN fi.review_score IS NULL THEN 'no review'
            WHEN fi.review_score <= 2    THEN '1-2 stars'
            WHEN fi.review_score = 3     THEN '3 stars'
            ELSE '4-5 stars'
        END                                                  AS review_band,
        IFF(r.customer_sk IS NOT NULL, 1, 0)                 AS returned
    FROM first_orders AS fi
    LEFT JOIN returners AS r
        ON r.customer_sk = fi.customer_sk
),

outcomes AS (
    SELECT 1 AS sort_key, 'all first orders' AS cut, 'all' AS grp, returned FROM cohort
    UNION ALL SELECT 2, 'timeliness', timeliness, returned FROM cohort
    UNION ALL SELECT 3, 'on time vs late', IFF(timeliness = 'on time or early', 'on time or early', 'late (any)'), returned FROM cohort
    UNION ALL SELECT 4, 'first-order review', review_band, returned FROM cohort
)

SELECT
    cut,
    grp                                                        AS first_order_experience,
    COUNT(*)                                                   AS people,
    SUM(returned)                                              AS returned,
    ROUND(100 * AVG(returned), 2)                              AS repeat_rate_pct,
    ROUND(100 * (AVG(returned) - 1.96 * SQRT(AVG(returned) * (1 - AVG(returned)) / COUNT(*))), 2) AS ci95_low_pct,
    ROUND(100 * (AVG(returned) + 1.96 * SQRT(AVG(returned) * (1 - AVG(returned)) / COUNT(*))), 2) AS ci95_high_pct
FROM outcomes
GROUP BY sort_key, cut, grp
ORDER BY sort_key, grp;


-- Q5b. Is the on-time versus late gap just a cohort-timing effect?
WITH params AS (
    SELECT 180 AS follow_up_days, MAX(purchase_date) AS data_end
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
),

first_orders AS (
    SELECT fo.customer_sk, fo.delivered_date, fo.is_late
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    CROSS JOIN params AS p
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, p.follow_up_days, fo.delivered_date) <= p.data_end
),

returners AS (
    SELECT DISTINCT fi.customer_sk
    FROM first_orders AS fi
    INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS later
        ON later.customer_sk = fi.customer_sk
    CROSS JOIN params AS p
    WHERE NOT later.is_first_order
      AND later.is_revenue_order
      AND later.purchase_date >= fi.delivered_date
      AND later.purchase_date <= DATEADD(day, p.follow_up_days, fi.delivered_date)
),

cohort AS (
    SELECT
        dd.year || '-Q' || dd.quarter           AS delivery_quarter,
        fi.is_late,
        IFF(r.customer_sk IS NOT NULL, 1, 0)    AS returned
    FROM first_orders AS fi
    INNER JOIN ELIO_OLIST.MARTS.DIM_DATE AS dd
        ON dd.date_day = fi.delivered_date
    LEFT JOIN returners AS r
        ON r.customer_sk = fi.customer_sk
)

SELECT
    delivery_quarter,
    COUNT_IF(NOT is_late)                                                          AS on_time_people,
    ROUND(100 * SUM(IFF(NOT is_late, returned, 0)) / NULLIF(COUNT_IF(NOT is_late), 0), 2) AS on_time_repeat_pct,
    COUNT_IF(is_late)                                                              AS late_people,
    ROUND(100 * SUM(IFF(is_late, returned, 0)) / NULLIF(COUNT_IF(is_late), 0), 2) AS late_repeat_pct,
    ROUND(100 * SUM(IFF(is_late, returned, 0)) / NULLIF(COUNT_IF(is_late), 0)
        - 100 * SUM(IFF(NOT is_late, returned, 0)) / NULLIF(COUNT_IF(NOT is_late), 0), 2)  AS gap_pct_points
FROM cohort
GROUP BY delivery_quarter
ORDER BY delivery_quarter;
