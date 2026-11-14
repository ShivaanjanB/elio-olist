-- Insight and campaign queries (brief B1 to B4): every number in analysis_answers.md comes from one of these.
--
--   . .\scripts\load_env.ps1
--   .\.venv\Scripts\python.exe ingest\run_sql.py sql\insight_queries.sql
--
-- Same conventions as sql/analytics_queries.sql: fully qualified names, definitions from docs/data_model.md section 8,
-- late = delivered date after the estimated date compared as dates (D18), came back = a later non-canceled order placed on
-- or after the first delivery day (D46), repeat windows only for people with enough follow-up (D53).
-- Choices made here are D56 to D60 in docs/decision_log.md. sql/insight_checks.sql recomputes the figures from staging.


-- =====================================================================================================================
-- I1a. Insight 1: review score by how late the order arrived (delivered orders that have a review).
--      Grain: one row per lateness band. days_vs_estimate: negative is early, positive is late.
--      Expect: about 4.2 to 4.3 stars when on time, then 3.29 at 1-3 days late, 2.10 at 4-7 and below 1.8 after a week.
-- =====================================================================================================================
SELECT
    CASE
        WHEN fo.days_vs_estimate <= -8 THEN 1
        WHEN fo.days_vs_estimate <= 0  THEN 2
        WHEN fo.days_vs_estimate <= 3  THEN 3
        WHEN fo.days_vs_estimate <= 7  THEN 4
        WHEN fo.days_vs_estimate <= 14 THEN 5
        ELSE 6
    END                                                          AS sort_key,
    CASE
        WHEN fo.days_vs_estimate <= -8 THEN 'early by 8+ days'
        WHEN fo.days_vs_estimate <= 0  THEN 'early by 0-7 days'
        WHEN fo.days_vs_estimate <= 3  THEN 'late 1-3 days'
        WHEN fo.days_vs_estimate <= 7  THEN 'late 4-7 days'
        WHEN fo.days_vs_estimate <= 14 THEN 'late 8-14 days'
        ELSE 'late 15+ days'
    END                                                          AS arrival,
    COUNT(*)                                                     AS reviewed_orders,
    ROUND(AVG(fo.review_score), 2)                               AS avg_score,
    ROUND(100 * COUNT_IF(fo.review_score <= 2) / COUNT(*), 1)    AS pct_1_2_stars,
    ROUND(100 * COUNT_IF(fo.review_score = 5) / COUNT(*), 1)     AS pct_5_stars
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL
  AND fo.review_score IS NOT NULL
GROUP BY 1, 2
ORDER BY sort_key;


-- I1b. The same, as the plain comparison: late against on time or early.
--      Expect: late 2.27 stars (62.4% give 1-2 stars) against 4.29 (9.3%).
SELECT
    IFF(fo.is_late, 'late', 'on time or early')                  AS arrival,
    COUNT(*)                                                     AS reviewed_orders,
    ROUND(AVG(fo.review_score), 2)                               AS avg_score,
    ROUND(100 * COUNT_IF(fo.review_score <= 2) / COUNT(*), 1)    AS pct_1_2_stars,
    ROUND(100 * COUNT_IF(fo.review_score = 5) / COUNT(*), 1)     AS pct_5_stars
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL
  AND fo.review_score IS NOT NULL
GROUP BY IFF(fo.is_late, 'late', 'on time or early')
ORDER BY arrival;


-- I1c. Is that gap just geography? Late and on-time review averages inside each state with at least 100 late reviewed
--      orders (D56). Late orders cluster in far-away states, so if those customers simply rated lower, the gap would
--      disappear within a state. It does not: the gap is 1.6 to 2.3 stars in every one of these states.
SELECT
    fo.customer_state,
    COUNT_IF(fo.is_late)                                                         AS late_reviewed,
    COUNT_IF(NOT fo.is_late)                                                     AS on_time_reviewed,
    ROUND(AVG(IFF(fo.is_late, fo.review_score, NULL)), 2)                        AS late_avg,
    ROUND(AVG(IFF(NOT fo.is_late, fo.review_score, NULL)), 2)                    AS on_time_avg,
    ROUND(AVG(IFF(NOT fo.is_late, fo.review_score, NULL))
        - AVG(IFF(fo.is_late, fo.review_score, NULL)), 2)                        AS gap_stars
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE fo.delivered_date IS NOT NULL
  AND fo.review_score IS NOT NULL
GROUP BY fo.customer_state
HAVING COUNT_IF(fo.is_late) >= 100
ORDER BY late_reviewed DESC;


-- I1d. The same gap with the state mix held fixed: each of those states weighted by its number of reviewed orders.
--      Expect about 1.9 stars, against 2.0 unadjusted.
WITH by_state AS (
    SELECT
        fo.customer_state,
        COUNT(*)                                          AS reviewed_orders,
        COUNT_IF(fo.is_late)                              AS late_reviewed,
        AVG(IFF(fo.is_late, fo.review_score, NULL))       AS late_avg,
        AVG(IFF(NOT fo.is_late, fo.review_score, NULL))   AS on_time_avg
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.delivered_date IS NOT NULL
      AND fo.review_score IS NOT NULL
    GROUP BY fo.customer_state
    HAVING COUNT_IF(fo.is_late) >= 100
)

SELECT
    COUNT(*)                                                                                   AS states,
    ROUND(SUM(reviewed_orders * on_time_avg) / SUM(reviewed_orders), 2)                        AS standardised_on_time_avg,
    ROUND(SUM(reviewed_orders * late_avg) / SUM(reviewed_orders), 2)                           AS standardised_late_avg,
    ROUND(SUM(reviewed_orders * (on_time_avg - late_avg)) / SUM(reviewed_orders), 2)           AS standardised_gap_stars
FROM by_state;


-- =====================================================================================================================
-- I2. Insight 2: repeat purchase against first-order experience, at 56, 90 and 180 days.
--     Cohort (D53): first order delivered, with 180 full days of follow-up after the delivery (63,874 people), so every
--     window is measured on the same people. Segments are the ones a campaign could target: first order late, first
--     order on time but reviewed 1-2 stars, and everyone else. The campaign segment is the first two together (D57).
--     Expect: the segment 0.65% / 0.89% / 1.38% against everyone else 0.91% / 1.20% / 1.84%.
--     This is an association, not proof that lateness or a bad review causes it (see analysis_answers.md).
-- =====================================================================================================================
WITH params AS (
    SELECT MAX(purchase_date) AS data_end
    FROM ELIO_OLIST.MARTS.FCT_ORDERS
),

cohort AS (
    SELECT
        fo.customer_sk,
        fo.delivered_date,
        fo.is_late,
        fo.review_score
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    CROSS JOIN params AS p
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, 180, fo.delivered_date) <= p.data_end
),

first_return AS (
    SELECT
        c.customer_sk,
        MIN(DATEDIFF(day, c.delivered_date, later.purchase_date)) AS days_to_return
    FROM cohort AS c
    INNER JOIN ELIO_OLIST.MARTS.FCT_ORDERS AS later
        ON later.customer_sk = c.customer_sk
    WHERE NOT later.is_first_order
      AND later.is_revenue_order                  -- a canceled follow-up is not a return
      AND later.purchase_date >= c.delivered_date
    GROUP BY c.customer_sk
),

people AS (
    SELECT
        CASE
            WHEN c.is_late            THEN 'late'
            WHEN c.review_score <= 2  THEN 'on time, 1-2 stars'
            ELSE 'on time, 3+ stars or no review'
        END                                         AS experience,
        (c.is_late OR c.review_score <= 2)          AS in_campaign_segment,
        fr.days_to_return
    FROM cohort AS c
    LEFT JOIN first_return AS fr
        ON fr.customer_sk = c.customer_sk
),

long_form AS (
    SELECT 1 AS sort_key, experience AS grp, days_to_return FROM people
    UNION ALL
    SELECT 2, 'campaign segment (late or 1-2 stars)', days_to_return FROM people WHERE in_campaign_segment
    UNION ALL
    SELECT 3, 'all first-time buyers', days_to_return FROM people
)

SELECT
    grp,
    COUNT(*)                                                     AS people,
    ROUND(100 * COUNT_IF(days_to_return <= 56)  / COUNT(*), 2)   AS repeat_56d_pct,
    ROUND(100 * COUNT_IF(days_to_return <= 90)  / COUNT(*), 2)   AS repeat_90d_pct,
    ROUND(100 * COUNT_IF(days_to_return <= 180) / COUNT(*), 2)   AS repeat_180d_pct
FROM long_form
GROUP BY sort_key, grp
ORDER BY sort_key, grp;


-- =====================================================================================================================
-- I3. The campaign: who it reaches, what it could earn and cost, and how big a test must be (D57 to D60).
--     Segment: people whose first order was delivered late or was reviewed 1-2 stars.
--     Everything marked (data) is measured; the three uplifts are ASSUMPTIONS, because nothing in this dataset says what a
--     voucher does. They are the whole reason for the test.
--       segment_per_year   first deliveries from 2017-09-01 to 2018-08-31, the last 12 reliable months (data)
--       baseline_56d       the segment's repeat rate within 8 weeks of delivery (data)
--       order value        average item price and freight on a person's later revenue orders (data)
--       uplift             extra repeat orders per segment member within 8 weeks: low 0.25 points (the gap to everyone
--                          else, i.e. an apology that only restores normal behaviour), base 0.5, high 1.0 (assumed)
--       voucher            free shipping on a redeemed order, capped at 15 (below the median freight of 17.19) to limit what
--                          a single redemption can cost (D58). Everyone in the segment who orders within 60 days is
--                          assumed to redeem it, baseline buyers too, which is the leakage
--     Revenue here is item revenue, not profit: margin is not in the data (see analysis_answers.md).
--     n_per_arm_needed: people per group to see the uplift with 80% power at the 5% level (two-sided).
-- =====================================================================================================================
WITH params AS (
    SELECT
        DATE '2017-09-01' AS flow_start,
        DATE '2018-08-31' AS flow_end,
        1.96              AS z_alpha,
        0.8416            AS z_power,
        15                AS voucher_cap
),

annual_flow AS (
    SELECT
        COUNT(*)                                                AS first_time_buyers_per_year,
        COUNT_IF(fo.is_late OR fo.review_score <= 2)            AS segment_per_year
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    CROSS JOIN params AS p
    WHERE fo.is_first_order
      AND fo.delivered_date BETWEEN p.flow_start AND p.flow_end
),

cohort AS (
    SELECT fo.customer_sk, fo.delivered_date, (fo.is_late OR fo.review_score <= 2) AS in_segment
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order
      AND fo.delivered_date IS NOT NULL
      AND DATEADD(day, 180, fo.delivered_date) <= (SELECT MAX(purchase_date) FROM ELIO_OLIST.MARTS.FCT_ORDERS)
),

baseline AS (
    SELECT
        COUNT_IF(c.in_segment AND EXISTS (
            SELECT 1
            FROM ELIO_OLIST.MARTS.FCT_ORDERS AS later
            WHERE later.customer_sk = c.customer_sk
              AND NOT later.is_first_order
              AND later.is_revenue_order
              AND later.purchase_date >= c.delivered_date
              AND later.purchase_date <= DATEADD(day, 56, c.delivered_date)
        )) / NULLIF(COUNT_IF(c.in_segment), 0)                  AS baseline_56d
    FROM cohort AS c
),

order_value AS (
    SELECT
        AVG(fo.items_price_total)                          AS avg_items_price,
        AVG(LEAST(fo.freight_total, p.voucher_cap))        AS avg_voucher_cost
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    CROSS JOIN params AS p
    WHERE NOT fo.is_first_order
      AND fo.is_revenue_order
      AND fo.item_count > 0
),

scenarios AS (
    SELECT 1 AS sort_key, 'low'  AS scenario, 0.0025 AS uplift
    UNION ALL SELECT 2, 'base', 0.0050
    UNION ALL SELECT 3, 'high', 0.0100
),

sized AS (
    SELECT
        s.sort_key,
        s.scenario,
        s.uplift,
        af.segment_per_year,
        af.first_time_buyers_per_year,
        b.baseline_56d,
        ov.avg_items_price,
        ov.avg_voucher_cost,
        af.segment_per_year * s.uplift                                   AS incremental_orders,
        af.segment_per_year * (b.baseline_56d + s.uplift)                AS redemptions,
        CEIL(POWER(p.z_alpha + p.z_power, 2)
             * (b.baseline_56d * (1 - b.baseline_56d)
                + (b.baseline_56d + s.uplift) * (1 - b.baseline_56d - s.uplift))
             / POWER(s.uplift, 2))                                        AS n_per_arm_needed
    FROM scenarios AS s
    CROSS JOIN annual_flow AS af
    CROSS JOIN baseline AS b
    CROSS JOIN order_value AS ov
    CROSS JOIN params AS p
)

SELECT
    scenario,
    ROUND(100 * uplift, 2)                                               AS uplift_points,
    segment_per_year,
    ROUND(100 * baseline_56d, 2)                                         AS baseline_56d_pct,
    ROUND(incremental_orders, 0)                                         AS extra_orders_per_year,
    ROUND(incremental_orders * avg_items_price, 0)                       AS extra_revenue,
    ROUND(redemptions * avg_voucher_cost, 0)                             AS voucher_cost,
    ROUND(incremental_orders * avg_items_price - redemptions * avg_voucher_cost, 0) AS revenue_less_voucher_cost,
    ROUND(redemptions * avg_voucher_cost / incremental_orders, 0)        AS voucher_cost_per_extra_order,
    ROUND(100 * (redemptions * avg_voucher_cost / incremental_orders) / avg_items_price, 0) AS break_even_margin_pct,
    ROUND(0.5 * redemptions * avg_voucher_cost, 0)                       AS test_voucher_cost_at_risk,
    n_per_arm_needed,
    ROUND(segment_per_year / 2, 0)                                       AS n_per_arm_available_in_a_year,
    n_per_arm_needed <= segment_per_year / 2                             AS detectable_in_a_year
FROM sized
ORDER BY sort_key;


-- I3b. The inputs behind those rows, stated on their own so each can be checked.
WITH params AS (
    SELECT DATE '2017-09-01' AS flow_start, DATE '2018-08-31' AS flow_end
)

SELECT
    COUNT(*)                                                    AS first_time_buyers_per_year,
    COUNT_IF(fo.is_late)                                        AS first_order_late,
    COUNT_IF(fo.review_score <= 2)                              AS first_order_1_2_stars,
    COUNT_IF(fo.is_late AND fo.review_score <= 2)               AS both,
    COUNT_IF(fo.is_late OR fo.review_score <= 2)                AS segment_per_year,
    ROUND(100 * COUNT_IF(fo.is_late OR fo.review_score <= 2) / COUNT(*), 1) AS segment_share_pct
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
CROSS JOIN params AS p
WHERE fo.is_first_order
  AND fo.delivered_date BETWEEN p.flow_start AND p.flow_end;

SELECT
    ROUND(AVG(fo.items_price_total), 2)       AS avg_items_price_on_later_orders,
    ROUND(AVG(fo.freight_total), 2)           AS avg_freight_on_later_orders,
    ROUND(AVG(LEAST(fo.freight_total, 15)), 2) AS avg_voucher_cost_capped_at_15,
    ROUND(MEDIAN(fo.freight_total), 2)        AS median_freight_on_later_orders,
    COUNT(*)                                  AS later_revenue_orders
FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
WHERE NOT fo.is_first_order
  AND fo.is_revenue_order
  AND fo.item_count > 0;

-- I3c. Why not RFM (B1): how little spread the frequency dimension has. Expect 96.88% of people with exactly one order.
SELECT
    COUNT(*)                                                  AS people,
    COUNT_IF(order_count = 1)                                 AS one_order_people,
    ROUND(100 * COUNT_IF(order_count = 1) / COUNT(*), 2)      AS pct_one_order,
    MAX(order_count)                                          AS most_orders_by_one_person
FROM ELIO_OLIST.MARTS.DIM_CUSTOMER;

-- I3d. How small an uplift can the test detect? The smallest uplift (in steps of 0.01 points) whose required group size
--      fits the people available, for 3, 6 and 12 months of enrolment split 50/50 (D59). 80% power, 5% level, two-sided.
WITH params AS (
    SELECT 1.96 AS z_alpha, 0.8416 AS z_power
),

segment AS (
    SELECT COUNT_IF(fo.is_late OR fo.review_score <= 2) AS segment_per_year
    FROM ELIO_OLIST.MARTS.FCT_ORDERS AS fo
    WHERE fo.is_first_order
      AND fo.delivered_date BETWEEN DATE '2017-09-01' AND DATE '2018-08-31'
),

baseline AS (
    SELECT 0.0065 AS baseline_56d          -- the segment's 8-week repeat rate from I2 (0.65%)
),

months AS (
    SELECT 3 AS months UNION ALL SELECT 6 UNION ALL SELECT 12
),

grid AS (
    SELECT (SEQ4() + 1) * 0.0001 AS uplift
    FROM TABLE(GENERATOR(ROWCOUNT => 300))
)

SELECT
    m.months                                                   AS months_of_enrolment,
    ROUND(sg.segment_per_year * m.months / 12 / 2, 0)          AS people_per_arm,
    ROUND(100 * MIN(g.uplift), 2)                              AS smallest_detectable_uplift_points
FROM months AS m
CROSS JOIN segment AS sg
CROSS JOIN baseline AS b
CROSS JOIN params AS p
INNER JOIN grid AS g
    ON CEIL(POWER(p.z_alpha + p.z_power, 2)
            * (b.baseline_56d * (1 - b.baseline_56d)
               + (b.baseline_56d + g.uplift) * (1 - b.baseline_56d - g.uplift))
            / POWER(g.uplift, 2))
       <= sg.segment_per_year * m.months / 12 / 2
GROUP BY m.months, sg.segment_per_year
ORDER BY m.months;
