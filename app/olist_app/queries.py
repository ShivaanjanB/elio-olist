"""The SQL the app runs against ELIO_OLIST.MARTS."""

ARRIVAL_BANDS = """
SELECT
    CASE WHEN fo.days_vs_estimate <= -8 THEN 1 WHEN fo.days_vs_estimate <= 0 THEN 2 WHEN fo.days_vs_estimate <= 3 THEN 3
         WHEN fo.days_vs_estimate <= 7 THEN 4 WHEN fo.days_vs_estimate <= 14 THEN 5 ELSE 6 END       AS sort_key,
    CASE WHEN fo.days_vs_estimate <= -8 THEN 'Early by 8+ days' WHEN fo.days_vs_estimate <= 0 THEN 'Early by 0-7 days'
         WHEN fo.days_vs_estimate <= 3 THEN 'Late 1-3 days' WHEN fo.days_vs_estimate <= 7 THEN 'Late 4-7 days'
         WHEN fo.days_vs_estimate <= 14 THEN 'Late 8-14 days' ELSE 'Late 15+ days' END                 AS arrival,
    COUNT(*)                                                                                          AS reviewed_orders,
    ROUND(AVG(fo.review_score), 2)                                                                    AS avg_score,
    ROUND(100 * COUNT_IF(fo.review_score <= 2) / COUNT(*), 1)                                         AS pct_1_2_stars,
    ROUND(100 * COUNT_IF(fo.review_score = 5) / COUNT(*), 1)                                          AS pct_5_stars
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL AND fo.review_score IS NOT NULL
GROUP BY 1, 2
ORDER BY sort_key
"""

ARRIVAL_SUMMARY = """
SELECT
    IFF(fo.is_late, 'late', 'on time or early')                                AS arrival,
    COUNT(*)                                                                   AS reviewed_orders,
    ROUND(AVG(fo.review_score), 2)                                             AS avg_score,
    ROUND(100 * COUNT_IF(fo.review_score <= 2) / COUNT(*), 1)                  AS pct_1_2_stars
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL AND fo.review_score IS NOT NULL
GROUP BY IFF(fo.is_late, 'late', 'on time or early')
"""

REVIEW_BY_STATE = """
SELECT
    fo.customer_state                                                          AS state,
    COUNT_IF(fo.is_late)                                                       AS late_reviewed,
    COUNT_IF(NOT fo.is_late)                                                   AS on_time_reviewed,
    ROUND(AVG(IFF(fo.is_late, fo.review_score, NULL)), 2)                      AS late_avg,
    ROUND(AVG(IFF(NOT fo.is_late, fo.review_score, NULL)), 2)                  AS on_time_avg
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL AND fo.review_score IS NOT NULL
GROUP BY fo.customer_state
HAVING COUNT_IF(fo.is_late) >= 100
ORDER BY late_reviewed DESC
"""

STATES = """
SELECT
    fo.customer_state                                                           AS state,
    COUNT(*)                                                                    AS orders,
    COUNT(fo.delivered_date)                                                    AS delivered_orders,
    ROUND(AVG(fo.days_to_deliver), 1)                                           AS avg_days_to_deliver,
    ROUND(100 * COUNT_IF(fo.is_late) / NULLIF(COUNT(fo.is_late), 0), 2)         AS late_pct,
    ROUND(AVG(fo.review_score), 2)                                              AS avg_review_score,
    ROUND(SUM(IFF(fo.is_revenue_order, fo.freight_total, 0)) / NULLIF(SUM(fo.revenue), 0), 3) AS freight_ratio,
    ROUND(SUM(fo.revenue), 2)                                                   AS revenue,
    COUNT(fo.delivered_date) >= 100                                             AS enough_data
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
GROUP BY fo.customer_state
"""

# People whose first order was delivered with 180 full days of follow-up (D53), by first-order experience, at three windows.
REPEAT_BY_EXPERIENCE = """
WITH params AS (SELECT MAX(purchase_date) AS data_end FROM ELIO_OLIST.MARTS.FCT_ORDERS),
cohort AS (
    SELECT fo.customer_sk, fo.delivered_date, fo.is_late, fo.review_score
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo CROSS JOIN params AS p
    WHERE fo.is_first_order AND fo.delivered_date IS NOT NULL AND DATEADD(day, 180, fo.delivered_date) <= p.data_end
),
first_return AS (
    SELECT c.customer_sk, MIN(DATEDIFF(day, c.delivered_date, later.purchase_date)) AS days_to_return
    FROM cohort AS c INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS later ON later.customer_sk = c.customer_sk
    WHERE NOT later.is_first_order AND later.is_revenue_order AND later.purchase_date >= c.delivered_date
    GROUP BY c.customer_sk
),
people AS (
    SELECT CASE WHEN c.is_late THEN 'Late' WHEN c.review_score <= 2 THEN 'On time, reviewed 1-2 stars'
                ELSE 'On time, 3+ stars or no review' END AS experience,
           (c.is_late OR c.review_score <= 2) AS in_campaign_segment,
           fr.days_to_return
    FROM cohort AS c LEFT JOIN first_return AS fr ON fr.customer_sk = c.customer_sk
),
long_form AS (
    SELECT 1 AS sort_key, experience AS grp, days_to_return FROM people
    UNION ALL SELECT 2, 'Campaign segment (late or 1-2 stars)', days_to_return FROM people WHERE in_campaign_segment
    UNION ALL SELECT 3, 'All first-time buyers', days_to_return FROM people
)
SELECT grp, COUNT(*) AS people,
       ROUND(100 * COUNT_IF(days_to_return <= 56)  / COUNT(*), 2) AS repeat_56d_pct,
       ROUND(100 * COUNT_IF(days_to_return <= 90)  / COUNT(*), 2) AS repeat_90d_pct,
       ROUND(100 * COUNT_IF(days_to_return <= 180) / COUNT(*), 2) AS repeat_180d_pct
FROM long_form GROUP BY sort_key, grp ORDER BY sort_key, grp
"""

# On time against late, by the quarter of the first delivery (same cohort and 180-day window).
REPEAT_BY_QUARTER = """
WITH params AS (SELECT MAX(purchase_date) AS data_end FROM ELIO_OLIST.MARTS.FCT_ORDERS),
first_orders AS (
    SELECT fo.customer_sk, fo.delivered_date, fo.is_late
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo CROSS JOIN params AS p
    WHERE fo.is_first_order AND fo.delivered_date IS NOT NULL AND DATEADD(day, 180, fo.delivered_date) <= p.data_end
),
returners AS (
    SELECT DISTINCT fi.customer_sk
    FROM first_orders AS fi INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS later ON later.customer_sk = fi.customer_sk
    WHERE NOT later.is_first_order AND later.is_revenue_order AND later.purchase_date >= fi.delivered_date
      AND later.purchase_date <= DATEADD(day, 180, fi.delivered_date)
),
cohort AS (
    SELECT dd.year || '-Q' || dd.quarter AS delivery_quarter, fi.is_late, IFF(r.customer_sk IS NOT NULL, 1, 0) AS returned
    FROM first_orders AS fi
    INNER JOIN ELIO_OLIST.MARTS.DIM_DATE AS dd ON dd.date_day = fi.delivered_date
    LEFT JOIN returners AS r ON r.customer_sk = fi.customer_sk
)
SELECT delivery_quarter,
       COUNT_IF(NOT is_late) AS on_time_people,
       ROUND(100 * SUM(IFF(NOT is_late, returned, 0)) / NULLIF(COUNT_IF(NOT is_late), 0), 2) AS on_time_repeat_pct,
       COUNT_IF(is_late) AS late_people,
       ROUND(100 * SUM(IFF(is_late, returned, 0)) / NULLIF(COUNT_IF(is_late), 0), 2) AS late_repeat_pct
FROM cohort GROUP BY delivery_quarter ORDER BY delivery_quarter
"""

# The inputs of the voucher calculator: the segment per year over the last 12 reliable months, its 8-week repeat rate,
# and what a later order is worth (the same inputs as I3 in sql/insight_queries.sql).
CAMPAIGN_INPUTS = """
WITH annual_flow AS (
    SELECT COUNT(*) AS first_time_buyers_per_year,
           COUNT_IF(fo.is_late OR fo.review_score <= 2) AS segment_per_year
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order AND fo.delivered_date BETWEEN DATE '2017-09-01' AND DATE '2018-08-31'
),
cohort AS (
    SELECT fo.customer_sk, fo.delivered_date, (fo.is_late OR fo.review_score <= 2) AS in_segment
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, 180, fo.delivered_date) <= (SELECT MAX(purchase_date) FROM ELIO_OLIST.MARTS.FCT_ORDERS)
),
baseline AS (
    SELECT COUNT_IF(c.in_segment AND EXISTS (
               SELECT 1 FROM ELIO_OLIST.MARTS.FCT_ORDERS AS later
               WHERE later.customer_sk = c.customer_sk AND NOT later.is_first_order AND later.is_revenue_order
                 AND later.purchase_date >= c.delivered_date AND later.purchase_date <= DATEADD(day, 56, c.delivered_date)
           )) / NULLIF(COUNT_IF(c.in_segment), 0) AS baseline_56d
    FROM cohort AS c
),
order_value AS (
    SELECT AVG(fo.items_price_total) AS avg_items_price
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE NOT fo.is_first_order AND fo.is_revenue_order AND fo.item_count > 0
)
SELECT af.segment_per_year, af.first_time_buyers_per_year, b.baseline_56d, ov.avg_items_price
FROM annual_flow AS af CROSS JOIN baseline AS b CROSS JOIN order_value AS ov
"""

LATER_ORDER_FREIGHTS = """
SELECT fo.freight_total
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE NOT fo.is_first_order AND fo.is_revenue_order AND fo.item_count > 0
"""

TABLES = {
    "arrival_bands": ARRIVAL_BANDS,
    "arrival_summary": ARRIVAL_SUMMARY,
    "review_by_state": REVIEW_BY_STATE,
    "states": STATES,
    "repeat_by_experience": REPEAT_BY_EXPERIENCE,
    "repeat_by_quarter": REPEAT_BY_QUARTER,
}
