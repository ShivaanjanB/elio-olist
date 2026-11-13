# Analytics results (Phase 6)

What the five queries in [`sql/analytics_queries.sql`](../sql/analytics_queries.sql) return, how to read each, and what to be
careful about. Every figure was recomputed from the staging views by a different route in
[`sql/analytics_checks.sql`](../sql/analytics_checks.sql) and agrees exactly (D55). Choices are in
[`decision_log.md`](decision_log.md) D51 to D55; definitions are in [`data_model.md`](data_model.md) section 8.

## Q1. Top 10 categories by revenue

Total revenue is 13,494,400.74 (items price on orders that are not canceled or unavailable, excluding freight).

| Rank | Category | Revenue | Share | Cumulative |
|---:|---|---:|---:|---:|
| 1 | health_beauty | 1,255,695.13 | 9.31% | 9.31% |
| 2 | watches_gifts | 1,198,185.21 | 8.88% | 18.18% |
| 3 | bed_bath_table | 1,035,964.06 | 7.68% | 25.86% |
| 4 | sports_leisure | 979,740.92 | 7.26% | 33.12% |
| 5 | computers_accessories | 904,322.02 | 6.70% | 39.82% |
| 6 | furniture_decor | 727,465.05 | 5.39% | 45.21% |
| 7 | housewares | 626,825.80 | 4.65% | 49.86% |
| 8 | cool_stuff | 620,770.49 | 4.60% | 54.46% |
| 9 | auto | 586,585.73 | 4.35% | 58.81% |
| 10 | garden_tools | 481,009.94 | 3.56% | 62.37% |

Reading it: revenue is spread out. No category passes 10%, and the top 3 hold about a quarter. The shares are of all revenue,
including the `unknown` category (610 products with no category), which does not reach the top 12.

## Q2. Monthly trend (2017-01 to 2018-08)

| Month | Orders | Revenue | Average order value | Orders MoM |
|---|---:|---:|---:|---:|
| 2017-01 | 787 | 120,098.27 | 152.60 | n/a |
| 2017-11 (peak) | 7,421 | 1,003,862.14 | 135.27 | +63.2% |
| 2018-01 | 7,187 | 945,456.29 | 131.55 | +27.9% |
| 2018-08 | 6,421 | 848,860.10 | 132.20 | +3.0% |

Reading it: growth came from the number of orders, which rose almost tenfold from January to November 2017, while the average
order value stayed between 124.76 and 152.60 in all 20 months. In 2018 orders level off between 6,145 and 7,187 a month. Five
months were left out because the data is too thin there (D51): 2016-09, 2016-10, 2016-12, 2018-09 and 2018-10.

## Q3. Anomalies

Sellers (Q3a). 627 sellers have at least 30 measurable orders. The average seller is late on 6.52% of orders (standard
deviation 4.89 points). 24 sellers have a z-score above 2, with late rates from 16.3% to 32.6%, and all 24 are also high against
the platform rate. The biggest by volume is a Maranhao seller (MA) with 389 orders and 19.0% late. Those 24 sellers hold 363 of
the 5,485 late orders among scored sellers, which is 6.6%.

Slow orders (Q3b, Q3c). The 99th percentile of delivery time is 46 days (median 10, slowest 210). 914 orders are above it.

| Group | Orders | Average days | Late | Average review | One-star share |
|---|---:|---:|---:|---:|---:|
| Above p99 | 914 | 63.4 | 96.2% | 1.79 | 69.2% |
| p99 or faster | 95,556 | 12.0 | 5.9% | 4.18 | 9.2% |

Reading it: lateness is spread widely, not concentrated in a few bad sellers, so removing the 24 would remove only about 6.6% of
late orders among scored sellers. Extreme delays are strongly tied to bad reviews. 433 of the 914 slow orders (47%) were bought in
November 2017 or February and March 2018, which suggests peaks overloading delivery, though this file does not test that.

## Q4. Breakdown by state

Highest late rates (states with enough data): AL 21.41%, MA 17.43%, SE 15.22%, PI 13.87%, CE 13.76%, BA 12.16%, RJ 12.11%.
Lowest: AM 2.76%, RO 2.88%, PR 4.04%, SP 4.49%, MG 4.57%. SP is also the fastest large state at 8.7 days on average.

The states with the highest late rates have the lowest average reviews (AL 3.76, MA 3.76, SE 3.81 against SP 4.17) and higher
freight ratios (MA 0.263, SE 0.239, AL 0.198 against SP 0.138). AM and RO have low late rates despite longer-than-average delivery times
(AM 26.4 days, RO 19.3 against SP 8.7), which suggests their promised dates are generous rather than delivery being fast. RR, AP and AC have fewer than 100
delivered orders and are flagged `enough_data = false`.

## Q5. Repeat rate by first-order experience

Cohort: 63,874 people whose first order was delivered with at least 180 days of follow-up. "Returned" means a later non-canceled
order within 180 days of that delivery (D53).

| First-order experience | People | Returned | Repeat rate | 95% interval |
|---|---:|---:|---:|---|
| All | 63,874 | 1,129 | 1.77% | 1.67 to 1.87 |
| On time or early | 59,330 | 1,074 | 1.81% | 1.70 to 1.92 |
| Late (any) | 4,544 | 55 | 1.21% | 0.89 to 1.53 |
| Late 1 to 7 days | 2,548 | 33 | 1.30% | 0.86 to 1.73 |
| Late 8 or more days | 1,996 | 22 | 1.10% | 0.64 to 1.56 |
| Review 1 to 2 stars | 8,505 | 115 | 1.35% | 1.11 to 1.60 |
| Review 3 stars | 5,523 | 95 | 1.72% | 1.38 to 2.06 |
| Review 4 to 5 stars | 49,381 | 912 | 1.85% | 1.73 to 1.97 |

Reading it: a late first delivery goes with a lower return rate, about 0.6 points or a third lower. The intervals do not
overlap, and within each delivery quarter from 2017-Q2 to 2018-Q2 (each with at least 300 late people) late people return less often (gaps of -0.14
to -0.99 points), so the gap is not an artefact of when people joined. 2016-Q4 and 2017-Q1 have too few late people to read.

Size it before building on it. Only 7.1% of the cohort (4,544 people) had a late first delivery. If every one of them returned at
the on-time rate, about 27 more people (4,544 x 0.60 points) would come back within 180 days in a cohort of 63,874. The overall
rate is 1.77%: nearly everyone who buys once does not buy again within six months, whether the delivery was on time or not.
This is an association, not proof that lateness causes it, because late deliveries are concentrated in other states (Q4) whose
customers may differ. Phase 7 should size the opportunity with these numbers before choosing the campaign.

## What these queries do not say

- Nothing here shows cause. Late delivery, low reviews and lower repeat rates move together; only a test with a holdout group could show that fixing one changes the other.
- The seller flag uses a cut-off of 2 and a minimum of 30 orders (D52); a different choice flags different sellers.
- The monthly trend stops at 2018-08 because the data does (D51).
