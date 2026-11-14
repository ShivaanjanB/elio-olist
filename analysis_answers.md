# Analysis and recommendation

Every number below comes from a query in [`sql/insight_queries.sql`](sql/insight_queries.sql) or
[`sql/analytics_queries.sql`](sql/analytics_queries.sql), and each was recomputed from the staging views by a different route in
[`sql/insight_checks.sql`](sql/insight_checks.sql) and [`sql/analytics_checks.sql`](sql/analytics_checks.sql). The query that
produces each figure is named in brackets, like [I1b]. Decisions are in [`docs/decision_log.md`](docs/decision_log.md) D56 to D60.

**The short version.** The business problem is repeat purchase: 96.9% of people buy once. Late delivery wrecks reviews and goes
with a lower repeat rate, but the group it affects is small, so the recommendation is a capped, randomised test that will show
what a voucher actually does, not a promise of a revenue jump.

## B1. Insight 1: late delivery against review score

**Method.** For delivered orders that have a review, compare the review score of orders that arrived after the promised date with
those that did not, then split by how many days late. Review scores are a 1 to 5 rating, so a distribution and an average say it
plainly, and the comparison needs no model. Late is measured as dates, because the promised date is always a date without a time
(decision D18).

**Result** [I1a, I1b].

| Arrival | Reviewed orders | Average score | Give 1 or 2 stars | Give 5 stars |
|---|---:|---:|---:|---:|
| On time or early | 89,443 | 4.29 | 9.3% | 62.3% |
| Late | 6,381 | 2.27 | 62.4% | 16.5% |
| Late 1 to 3 days | 1,852 | 3.29 | 32.1% | 33.2% |
| Late 4 to 7 days | 1,748 | 2.10 | 67.7% | 14.1% |
| Late 8 to 14 days | 1,446 | 1.67 | 80.2% | 6.8% |
| Late 15 or more days | 1,335 | 1.72 | 78.4% | 7.2% |

**What it says.** Missing the promised date costs about a star even when it is only one to three days, and by a week the average
is below 2. Orders that arrive early, even by more than a week, score about the same as those on the day (4.19 to 4.32), so the damage
comes from a broken promise, not from slowness itself. The 914 slowest orders (over 46 days) average 1.79 stars [Q3c].

**Is it just geography?** Late rates are highest in far-away states, so customers there might simply rate lower. They do not: inside
each of the 14 states with at least 100 late reviewed orders, late orders score 1.6 to 2.3 stars lower than on-time ones [I1c], and
with the state mix held fixed the gap is 1.92 stars (4.29 against 2.37) [I1d].

**Why not RFM.** 93,099 of 96,096 people (96.88%) have exactly one order [I3c], so the frequency part of RFM has almost no
spread and the model would collapse to recency and spend. The question here is how one experience relates to a second purchase, so
the method compares groups defined by that experience.

## B2. Insight 2: repeat purchase against the first-order experience

**Method.** Group customers by `customer_unique_id` (the person, since `customer_id` changes on every order). Take people whose
first order was delivered and who have at least 180 days of data after that delivery, so everyone had the same time to come
back (63,874 people). Count them as returning if they placed a later, non-canceled order on or after the delivery day. Compare
the rate within 56, 90 and 180 days by the first-order experience (decisions D46, D53).

**Result** [I2].

| First-order experience | People | Within 56 days | Within 90 days | Within 180 days |
|---|---:|---:|---:|---:|
| Late | 4,544 | 0.59% | 0.77% | 1.21% |
| On time, reviewed 1 or 2 stars | 5,621 | 0.69% | 0.98% | 1.51% |
| On time, 3 or more stars or no review | 53,709 | 0.91% | 1.20% | 1.84% |
| **Campaign segment (late or 1 to 2 stars)** | **10,165** | **0.65%** | **0.89%** | **1.38%** |
| All first-time buyers | 63,874 | 0.87% | 1.15% | 1.77% |

**What it says.** People whose first order went badly come back about a quarter to a third less often, at every window. The
difference in the 180-day rate (1.21% against 1.81% for on-time) has 95% intervals that do not overlap [Q5], and it appears inside
each delivery quarter from 2017-Q2 to 2018-Q2 [Q5b], so it is not an artefact of when people joined. The larger fact is the
baseline: even people whose first order went fine return only 1.84% of the time within six months.

**This is an association, not proof of cause.** Late orders are concentrated in states whose customers may differ in other ways, and
a bad review could reflect a bad product as much as a bad delivery. Only a randomised test can say whether fixing the experience
changes what people do.

## B3. Recommendation: a service-recovery test

**Do one thing: test an apology and a capped free-shipping voucher on the customers who had a bad first order, with a random
holdout.** The aim is to find out what a voucher does to repeat purchase, at a cost that cannot hurt, before anyone spends on all
the first-time buyers.

| | |
|---|---|
| **Who** | People whose first order was delivered late or was reviewed 1 or 2 stars: about **11,900 a year**, 16.4% of the 72,907 first-time buyers [I3b]. |
| **Offer** | An apology message and free shipping up to R$15 on their next order, valid for 60 days. The cap is below the median freight (R$17.10 on later orders), so one redemption costs R$13.78 on average, against R$23.03 for uncapped freight [I3b, D58]. |
| **Test** | Randomise half of them to the offer and half to nothing (50/50, D59). Enrolment runs as first orders are delivered. |
| **Primary measure** | Share who place a later order within 8 weeks of delivery, offer against holdout. |
| **Early signal** | Share who redeem the voucher by week 2. |
| **Guardrail** | Voucher cost per extra order. Stop the test if it exceeds the margin earned on an order (see below). |

**What it could be worth** [I3]. Only the first four rows of inputs are measured. The three uplifts are assumptions, because nothing
in this data says what a voucher does. The low case is an apology that merely restores normal behaviour (the 0.26-point gap to
everyone else at 8 weeks).

| Scenario | Assumed uplift in the 8-week repeat rate (points) | Extra orders a year | Extra item revenue | Voucher cost | Revenue less voucher cost | Voucher cost per extra order | Margin needed to break even | Test spend at risk |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Low | 0.25 | 30 | R$3,703 | R$1,480 | R$2,224 | R$50 | 40% | R$740 |
| Base | 0.50 | 60 | R$7,407 | R$1,891 | R$5,516 | R$32 | 26% | R$945 |
| High | 1.00 | 119 | R$14,814 | R$2,714 | R$12,100 | R$23 | 18% | R$1,357 |

Measured inputs: 11,937 people a year, 0.65% of them reorder within 8 weeks anyway, a later order averages R$124.10 of items, and
a voucher costs R$13.78. Revenue is item revenue, not profit: the dataset has no margin. The last two columns matter more than the
money: the voucher only makes a profit if the margin on an extra order exceeds 18% to 40% of its item revenue, and everyone in the
segment who would have ordered anyway also uses the voucher. Test spend at risk is the treated half's voucher cost if the whole
campaign ran at that scenario; vouchers cost money only when used.

**Be honest about the size.** The prize is small: R$2k to R$12k a year against annual item revenue of roughly R$10 million [Q2]. This is a
learning test, not a growth engine. If the voucher works for this segment, the same design can be tried on all 72,907 first-time
buyers a year, six times as many people, where the base rate is similar and nothing says the effect would be the same. That
decision should wait for the result.

**Sample size, with no false precision** [I3, I3d]. With a base rate of 0.65% you need thousands of people per group. A year of
enrolment gives 5,969 per group, enough to detect an uplift of about **0.49 points** (the base case needs 5,593 per group; the low
case needs 19,294, so it cannot be seen). Six months detects 0.73 points and three months 1.12. If the true effect is smaller than
that, the test will not find it and the result should be read as "no effect larger than this".

**Decision rule.** Scale the voucher only if the 8-week uplift is real (the interval excludes zero) and the voucher cost per extra
order is below the margin earned on an order. Finance supplies the margin, which the data does not have.

**Fallback.** If the test shows no effect, the cheaper lever is the delivery promise. A one to three day slip costs a full
star (Insight 1), and the states with the highest late rates are AL (21.4%), MA (17.4%) and SE (15.2%) [Q4]. Resetting estimated
delivery dates or seller service levels there needs no voucher. This file does not size it, because the data cannot say what a
longer promise does to purchases.

## Caveats

- **Association, not cause** for both insights; only the test can show cause.
- **Margin is unknown.** Every money figure is item revenue before costs, and the voucher break-even depends on a margin the data lacks.
- **The three uplifts are assumptions.** The data measures the base rate, the segment size, the order value and the voucher cost; it cannot measure a response to a voucher it has never seen.
- **Small effects, small segment.** The 8-week gaps are a quarter to a third of a percentage point, which only large groups can show reliably; that is why the test is sized by the smallest effect it can see.
- **The "within 180 days" windows exclude recent buyers.** People delivered after 2018-04-20 are left out so everyone had the same time (D53).
- **Old data, one marketplace.** The orders run from 2016 to 2018 and were sold through Olist; rates today may differ.
- **Late is judged against Olist's own promised dates**, which are generous in some states (AM and RO have low late rates despite long deliveries), so late is not the same as slow.
- **Reviews are voluntary.** 98,673 of 99,441 orders have one, so selection is small, but angry and delighted customers are more likely to write.
- **No time zone** in the source timestamps (D09), which can move an order by a day around midnight; delivery and lateness are measured in whole days so the effect is small.
- **Customers whose first order was canceled** are not in the repeat analysis (they have no delivery to react to); there are 1,153 of them (D39).

## Top 3 production data checks

Mapped to the data-quality dimensions they protect, with what exists today.

| # | Check | Protects | Status |
|---|---|---|---|
| 1 | **Key integrity at every grain,** composite keys included: `unique` and `not_null` on each key, `unique_combination_of_columns` on `(order_id, order_item_id)`, `(order_id, payment_sequential)` and `(review_id, order_id)`, `relationships` on every foreign key, and exactly one first order per person. | Uniqueness, validity | **Running** in `dbt build` (staging, intermediate and marts). A duplicate key would silently inflate every total. |
| 2 | **Reconciliation:** raw against staging row counts, marts against staging rows and sums, and per-order payments against item price plus freight within a tolerance, warning when more than 1% of orders differ by over R$1.00. | Accuracy, consistency | **Running.** Today 0.25% of orders are outside tolerance (249 of 98,665), so the warning has 4 times headroom. |
| 3 | **Freshness and volume:** `loaded_at_field: _loaded_at` with a warning if no load arrives within the expected window, plus a daily check that the latest load's row count is within a set band of the recent average. | Timeliness, completeness | **Described, not configured.** The data is a one-off export, so a freshness rule would go stale by design and warn forever. It becomes the first check to add once loading is scheduled (decision D60). |

## B4. Client memo

<!-- memo:start -->
**To: CFO. Subject: A voucher test for repeat purchase**

Almost nobody returns: 96.9% of customers buy once, and only 1.8% reorder within six months.

Late delivery damages reviews. Orders arriving after the promised date average 2.27 stars against 4.29, and 62% get one or two stars. Even one to three days late costs about a star, in every large state.

First orders that went badly also return less: 1.4% within six months against 1.8%. That is association, not proof of cause.

Recommendation: offer customers whose first order was late or rated one or two stars (about 11,900 a year) an apology and free shipping up to R$15, valid 60 days. Hold out half at random; compare orders within eight weeks.

Size: if the voucher adds 0.25 to 1.0 points of repeat orders, that is 30 to 119 orders and R$3.7k to R$14.8k of item revenue a year, against R$1.5k to R$2.7k of vouchers. A year of enrolment detects only about half a point.

Ask: approve the test and share your margin; the voucher pays back only above 18% to 40%. If it fails, reset delivery promises in AL, MA and SE.
<!-- memo:end -->

## Where each number comes from

| Figure | Query | Independent check |
|---|---|---|
| Review score by lateness, per state, state-adjusted gap | I1a, I1b, I1c, I1d | C6 |
| Share of people with one order | I3c | Pinned by `marts_golden_numbers` (dbt): 96,096 people, 2,997 with more than one order |
| Repeat rates at 56, 90 and 180 days, segment sizes | I2 | C7, C5 |
| Segment per year, base rate, order value, voucher cost | I3, I3b | C8 |
| Scenario table and test size | I3, I3d | arithmetic on the C8 inputs |
| Slowest 914 orders, late rates by state | Q3b, Q3c, Q4 | C3, C4 |
