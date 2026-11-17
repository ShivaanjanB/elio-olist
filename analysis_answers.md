# Analysis and recommendation

Every number below comes from a query in [`sql/insight_queries.sql`](sql/insight_queries.sql) or
[`sql/analytics_queries.sql`](sql/analytics_queries.sql), and I recomputed each one from the staging views by a different route in
[`sql/insight_checks.sql`](sql/insight_checks.sql) and [`sql/analytics_checks.sql`](sql/analytics_checks.sql). The query behind
each figure is named in brackets, like [I1b]. The decisions are in [`docs/decision_log.md`](docs/decision_log.md), D56 to D60 and D74.

**The short version.** The problem is repeat purchase: 96.9% of people buy once. Late delivery wrecks reviews and goes with a lower
repeat rate, but the group it hits is small. So I'm recommending a capped, randomised test that shows what a voucher actually does,
rather than promising a jump in revenue.

## Context: who Olist is

In 2016 to 2018 Olist ran the "Olist Store": one store on Brazil's big marketplaces, selling for thousands of small merchants who
shipped their own orders. Once the parcel arrived, or the promised date passed, the shopper got a review survey by email
([dataset description](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)). Two things follow from that:

- **Shoppers belong to the marketplace.** They come back to Mercado Livre or Amazon and pick whichever seller suits them, so a low
  repeat rate for one store is partly built in.
- **Reviews and late deliveries are public.** Marketplaces score sellers on late shipments, cancellations and complaints, and a
  worse score means less visibility ([Mercado Livre's seller reputation](https://developers.mercadolivre.com.br/en_us/sellers-reputation)).
  So a bad review costs more than one customer.

Olist has since moved into software for small retailers and closed the Olist Store business in 2026
([Brazil Journal](https://braziljournal.com/a-olist-matou-o-negocio-que-a-fez-unicornio-o-novo-modelo-e-melhor/)).

## B1. Commercial insights

Two insights. Each one has the finding, how I got it, and why someone running the business should care.

### Insight 1: late delivery against review score

**Method.** For delivered orders with a review, I compared the scores of orders that arrived after the promised date with those that didn't, then split the late ones by days late. Review scores are a 1 to 5 rating, so a distribution and an average say it
plainly, and the comparison needs no model. Late is measured in dates, because the promised date is always a date with no time
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

**What it says.** Missing the promised date costs about a star, even when it's only one to three days, and by a week the average
is below 2. Orders that arrive early, even by more than a week, score about the same as on-time ones (4.19 to 4.32). It's the broken promise that hurts, not the slowness. The 914 slowest orders (over 46 days) average 1.79 stars [Q3c].

**Is it just geography?** Late rates are highest in far-away states, so customers there might simply rate lower. They don't. In each of the 14 states with at least 100 late reviewed orders, late orders score 1.6 to 2.3 stars lower [I1c]. With the state mix held fixed, the gap is 1.92 stars (4.29 against 2.37) [I1d].

**When was the review written?** The survey goes out when the parcel arrives or the promised date passes, whichever comes first.
So most late customers were asked before their parcel turned up.

| Arrival | Reviewed orders | Answered before the parcel arrived | Score if answered before | Score if answered after |
|---|---:|---:|---:|---:|
| On time or early | 89,443 | 153 (0.2%) | 3.86 | 4.29 |
| Late | 6,381 | 4,086 (64.0%) | 1.63 | 3.41 |

[I1e] Lateness still costs close to a star once the parcel arrives (3.41 against 4.29). But most of the drop to 2.27 comes from
people rating a parcel they haven't got yet (D74).

**Why it matters.** A broken delivery promise is the one driver of bad reviews that operations can control, and reviews shape what
the next buyer sees on the marketplace. It also shows that the promise matters more than the speed: arriving early earns nothing
extra, and arriving late costs a star even by a day or two. And asking for a review on the promised date makes it worse.

**Why not RFM.** 93,099 of 96,096 people (96.88%) have exactly one order [I3c], so the frequency part of RFM barely varies and the
model would collapse to recency and spend. The question here is how one experience relates to a second purchase, so I compared
groups defined by that experience instead.

### Insight 2: repeat purchase against the first-order experience

**Method.** I grouped customers by `customer_unique_id` (the person, since `customer_id` changes on every order). I took the 63,874 people whose first order was delivered at least 180 days before the data ends, so everyone had the same time to come back. They count as returning if they placed a later, non-canceled order on or after the delivery day. Then I compared
the rate within 56, 90 and 180 days by the first-order experience (decisions D46, D53).

**Result** [I2].

| First-order experience | People | Within 56 days | Within 90 days | Within 180 days |
|---|---:|---:|---:|---:|
| Late | 4,544 | 0.59% | 0.77% | 1.21% |
| On time, reviewed 1 or 2 stars | 5,621 | 0.69% | 0.98% | 1.51% |
| On time, 3 or more stars or no review | 53,709 | 0.91% | 1.20% | 1.84% |
| **Campaign segment (late or 1 to 2 stars)** | **10,165** | **0.65%** | **0.89%** | **1.38%** |
| All first-time buyers | 63,874 | 0.87% | 1.15% | 1.77% |

**What it says.** People whose first order went badly come back about a quarter to a third less often, at every window. At 180 days it's 1.21% against 1.81% for on-time, and the 95% intervals don't overlap [Q5]. The gap shows up in every delivery quarter from 2017-Q2 to 2018-Q2 [Q5b], so it isn't about when people joined. The bigger fact is the
baseline: even people whose first order went fine only return 1.84% of the time within six months.

**Why it matters.** Revenue is customers times orders per customer times order value, and the weak part is orders per customer: only 1.8% of first-time buyers come back within six months. A group that returns even less after a bad experience is a
good place to test a fix.

**This is an association, not proof of cause.** Late orders cluster in states whose customers may differ in other ways, and a bad review could be about the product as much as the delivery. Only a randomised test can say whether fixing the experience
changes what people do.

## B2. The recommendation: a service-recovery test

**Do one thing: test an apology and a capped free-shipping voucher on the customers who had a bad first order, with a random
holdout.** The aim is to find out what a voucher does to repeat purchase, at a cost that can't hurt, before anyone spends on all
the first-time buyers.

| | |
|---|---|
| **Who** | People whose first order was delivered late or was reviewed 1 or 2 stars: about **11,900 a year**, 16.4% of the 72,907 first-time buyers [I3b]. |
| **Offer** | An apology message and free shipping up to R$15 on their next order, valid for 60 days. The cap is below the median freight (R$17.10 on later orders), so one redemption costs R$13.78 on average, against R$23.03 for uncapped freight [I3b, D58]. |
| **Test** | Randomise half of them to the offer and half to nothing (50/50, D59). Enrolment runs as first orders are delivered. |
| **Primary measure** | Share who place a later order within 8 weeks of delivery, offer against holdout. |
| **Early signal** | Share who redeem the voucher by week 2. |
| **Guardrail** | Voucher cost per extra order. Stop the test if it exceeds the margin earned on an order (see below). |

**What it could be worth** [I3]. Four inputs are measured (they're listed under the table). The three uplifts are assumptions,
because nothing in this data says what a voucher does. The low case is an apology that just restores normal behaviour (the
0.26-point gap to everyone else at 8 weeks).

| Scenario | Assumed uplift in the 8-week repeat rate (points) | Extra orders a year | Extra item revenue | Voucher cost | Revenue less voucher cost | Voucher cost per extra order | Margin needed to break even | Test spend at risk |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Low | 0.25 | 30 | R$3,703 | R$1,480 | R$2,224 | R$50 | 40% | R$740 |
| Base | 0.50 | 60 | R$7,407 | R$1,891 | R$5,516 | R$32 | 26% | R$945 |
| High | 1.00 | 119 | R$14,814 | R$2,714 | R$12,100 | R$23 | 18% | R$1,357 |

The measured inputs are 11,937 people a year, 0.65% of whom reorder within 8 weeks anyway, a later order averaging R$124.10 of
items, and a voucher costing R$13.78. Revenue here is item revenue, not profit, because the dataset has no margin. The last two columns matter more than the money. The voucher only pays if the margin on an extra order is above 18% to 40% of its item revenue, and that bar is high because anyone who'd have ordered anyway uses the voucher too. "Test spend at risk" is the treated half's voucher cost at that scenario. Vouchers only cost money when they're used.

**How big is this, really?** The prize is small: R$2k to R$12k a year against annual item revenue of roughly R$10 million [Q2]. This
is a learning test, not a growth engine. If it works for this segment, the same design could be tried on all 72,907 first-time buyers a year, six times as many people. The base rate there is similar, but nothing says the effect would be.
That decision should wait for the result.

**Sample size.** [I3, I3d] With a base rate of 0.65% you need thousands of people per group. A year of enrolment gives 5,969 per group, enough to detect about **0.49 points**. The base case needs 5,593 per group; the low case needs 19,294, so it can't be seen. Six months detects 0.73 points and three months 1.12. If the true effect is smaller than that, the
test won't find it, and the result should be read as "no effect larger than this".

**Decision rule.** Scale the voucher only if the 8-week uplift is real (the interval excludes zero) and the voucher cost per extra
order is below the margin earned on an order. Finance would supply the margin, because the data doesn't have it.

**A near-free test to run alongside it.** At the promised date, send late customers a short message saying where their order is,
and send the review survey only once the parcel arrives. It costs almost nothing and goes straight at the 1.63-star reviews written
before delivery [I1e]. It needs its own random holdout, measured on review score and the 8-week repeat rate, so its effect can be
told apart from the voucher's (D74).

**Fallback.** If the test shows no effect, the cheaper lever is the delivery promise. A one to three day slip costs a full
star (Insight 1), and the states with the highest late rates are AL (21.4%), MA (17.4%) and SE (15.2%) [Q4]. Resetting estimated
delivery dates or seller service levels there needs no voucher. I haven't sized it here, because the data can't say what a
longer promise does to purchases.

## B3. Assumptions, caveats and data quality

### Assumptions and caveats

- **Association, not cause** for both insights. Only the test can show cause.
- **Margin is unknown.** Every money figure is item revenue before costs, and the voucher break-even depends on a margin the data doesn't have.
- **The three uplifts are assumptions.** The data measures the base rate, the segment size, the order value and the voucher cost. It can't measure a response to a voucher it has never seen.
- **Small effects, small segment.** The 8-week gaps are a quarter to a third of a percentage point, which only large groups can show reliably. That's why the test is sized by the smallest effect it can see.
- **The "within 180 days" windows exclude recent buyers.** People delivered after 2018-04-20 are left out so everyone had the same time (D53).
- **Old data, one marketplace.** The orders run from 2016 to 2018 and were sold through Olist, so rates today may differ.
- **The voucher has to fit marketplace rules.** Marketplaces control how sellers contact and reward buyers, so the offer may need to run through the marketplace's own promotions. That needs checking before the test starts.
- **Low repeat is partly structural.** On a marketplace, shoppers come back to the marketplace and choose any seller, so 96.9% buying once from one store is less alarming than it looks.
- **Late is judged against Olist's own promised dates,** which are generous in some states (AM and RO have low late rates despite long deliveries), so late isn't the same as slow.
- **Reviews are voluntary.** 98,673 of 99,441 orders have one, so selection is small, but angry and delighted customers are more likely to write.
- **No time zone** in the source timestamps (D09), which can move an order by a day around midnight. Delivery and lateness are measured in whole days, so the effect is small.
- **Customers whose first order was canceled** aren't in the repeat analysis, because they have no delivery to react to. There are 1,153 of them (D39).

### Top 3 production data checks

What I'd check in production, which data-quality dimension each one protects, and where each stands today.

| # | Check | Protects | Status |
|---|---|---|---|
| 1 | **Key integrity at every grain,** composite keys included: `unique` and `not_null` on each key, `unique_combination_of_columns` on `(order_id, order_item_id)`, `(order_id, payment_sequential)` and `(review_id, order_id)`, `relationships` on every foreign key, and exactly one first order per person. | Uniqueness, validity | **Running** in `dbt build` (staging, intermediate and marts). A duplicate key would silently inflate every total. |
| 2 | **Reconciliation:** raw against staging row counts, marts against staging rows and sums, and per-order payments against item price plus freight within a tolerance, warning when more than 1% of orders differ by over R$1.00. | Accuracy, consistency | **Running.** Today 0.25% of orders are outside tolerance (249 of 98,665), so the warning has 4 times headroom. |
| 3 | **Freshness and volume:** `loaded_at_field: _loaded_at` with a warning if no load arrives within the expected window, plus a daily check that the latest load's row count is within a set band of the recent average. | Timeliness, completeness | **Described, not configured.** The data is a one-off export, so a freshness rule would go stale by design and warn forever. It becomes the first check to add once loading is scheduled (decision D60). |

## B4. Client memo

<!-- memo:start -->
**To: CFO. Subject: What we built, what it found, and one test to run**

What we built: the Olist order files are loaded into Snowflake, cleaned and checked in dbt, and modelled into tables that answer business questions directly. Every figure below was recomputed a second way.

What it found: almost nobody returns. 96.9% of customers buy once, and 1.8% reorder within six months. Late delivery damages reviews: orders arriving after the promised date average 2.27 stars against 4.29, and customers whose first order was late return less (1.2% against 1.8% for on-time orders). That is association, not proof of cause.

Next step: send the roughly 11,900 customers a year whose first order was late or rated one or two stars an apology and free shipping up to R$15, holding out half at random. If it adds 0.25 to 1.0 points of repeat orders, that is R$3.7k to R$14.8k of item revenue a year against R$1.5k to R$2.7k of vouchers. A year of enrolment detects only about half a point.

Please approve the test and share your margin: the voucher pays back only above 18% to 40%. If it fails, we reset delivery promises in AL, MA and SE.
<!-- memo:end -->

## B5. LLM use case (proposed, not built)

**Tag why customers were unhappy, from their own words.** About 41,000 of the 99,224 reviews carry a comment (58,247 are empty), written
in Portuguese. A language model would read each comment and label the complaint reason. That shows whether late delivery is the whole story or something else sits behind the low scores. That checks the recommendation in B2 before money is spent on
it: a voucher fits a delivery complaint, not a damaged or wrong item.

| | |
|---|---|
| **Example prompt** | "Read this Portuguese customer review and label the main reason for any complaint: late delivery, damaged or defective product, wrong or missing item, seller or service, or none. Reply with up to two labels and a confidence from 0 to 1." Written for illustration, not taken from the data: "O produto chegou 15 dias atrasado e a caixa estava amassada" (the product arrived 15 days late and the box was crushed). |
| **Data retrieved** | `review_comment_message` and the score from `stg_olist__order_reviews`, joined to `fct_orders` on `order_id` for the late flag. The comment text stops at staging today, so this needs one new model. |
| **Output** | For the example: late delivery and damaged product, with a confidence for each. Stored as one row per review, then summed into counts of each reason for late orders against on-time orders. |
| **Main risk** | Wrong labels on slang and misspellings; personal details in free text (names, phone numbers) leaving the account; and cost, because about 41,000 comments would be classified. |
| **Mitigation** | Run it inside Snowflake with a Cortex classification function (such as `AI_CLASSIFY`) so the text stays in the account. Hand-label 100 to 200 comments first and report how often the model agrees before anyone relies on it. Try 20 rows to see the cost, and keep the account's 20-credit monthly cap in force. Use the result only as counts by reason, never to message a customer. |

**Status: proposed, not run.** I haven't checked whether Cortex is available in this account's region, and a half-tested call
shouldn't be presented as working. I set the other options aside for similar reasons. Plain-English questions of the marts would duplicate the five queries and risk wrong joins on money. A model-drafted memo would put model-written numbers next to the memo. And model-written apologies would change the voucher treatment the test relies on.

## Where each number comes from

| Figure | Query | Independent check |
|---|---|---|
| Review score by lateness, per state, state-adjusted gap | I1a, I1b, I1c, I1d | C6 |
| Reviews answered before the parcel arrived | I1e | C9 |
| Share of people with one order | I3c | Pinned by `marts_golden_numbers` (dbt): 96,096 people, 2,997 with more than one order |
| Repeat rates at 56, 90 and 180 days, segment sizes | I2 | C7, C5 |
| Segment per year, base rate, order value, voucher cost | I3, I3b | C8 |
| Scenario table and test size | I3, I3d | arithmetic on the C8 inputs |
| Slowest 914 orders, late rates by state | Q3b, Q3c, Q4 | C3, C4 |
