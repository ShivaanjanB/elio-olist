# Decision log

The design decisions, what I picked each one over, and why. The queries behind the data findings are in
[`relationship_checks.sql`](relationship_checks.sql) and [`type_and_design_checks.sql`](type_and_design_checks.sql), the model is in
[`data_model.md`](data_model.md), and the load decisions are in [`../ingest/LOAD_NOTES.md`](../ingest/LOAD_NOTES.md).

Written 2026-11-13 (D01 to D62), 2026-11-14 (D63 to D71) and 2026-11-16 (D72 and D73).

| ID | Decision | Instead of | Why |
|---|---|---|---|
| D01 | Design backwards from the five analytics questions | Building forwards from the source tables | Every mart column has a question behind it, and no question is missing a column. |
| D02 | Four schemas: `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS`, with a `generate_schema_name` override so dbt uses exactly those names | dbt's default prefixed names (`RAW_STAGING`) | Readable layers and predictable queries. The default is for shared dev setups, which this isn't. |
| D03 | Staging and intermediate are views, marts are tables | Ephemeral intermediate models; everything as tables | Views are always current and can be queried while debugging. Marts are what analysts hit, so the joins are paid for once. |
| D04 | Staging is 1:1 with the source files: rename, cast, de-duplicate, nothing else | Business logic in staging | Keeps staging boring and easy to audit. Anything surprising lives in a named model further down. |
| D05 | The `customers` file is the address (`customer_id`); the person (`customer_unique_id`) is derived in intermediate | Splitting the file into two staging models | One staging model per file (D04). There are 99,441 `customer_id`s but only 96,096 people. |
| D06 | Naming: `stg_olist__*`, `int_*`, `dim_*`, `fct_*`; the misspelt `*_lenght` columns become `*_length` in staging | Keeping the source spelling | Fixed once, so nothing downstream carries the typo and RAW stays as received. |
| D07 | Column types: ids `VARCHAR(32)`, state `VARCHAR(2)`, zip `VARCHAR(5)`, timestamps `TIMESTAMP_NTZ`, money `NUMBER(12,2)`, counts `NUMBER(10,0)`, score `NUMBER(1,0)` | All `VARCHAR`, or all `NUMBER` | Each type was checked against the data first: every id is 32 characters, every timestamp parses, and no money value has more than 2 decimals. |
| D08 | Zip prefixes stay text | A numeric zip | A number drops the leading zero, and 23,995 customer and 1,027 seller prefixes start with `0`. |
| D09 | No time-zone conversion (`TIMESTAMP_NTZ`) | Converting to UTC or Sao Paulo time | The source has no zone, so converting would invent information, and every comparison is between timestamps from the same source. |
| D10 | Natural keys in staging and intermediate; hashed surrogate keys on the dimensions; a one-column key on `fct_order_items` | Natural keys everywhere; surrogate keys on every fact | A hash is a convention, not a protection: it gives one uniform join key that survives rebuilds, but it changes if the source key does. |
| D11 | Keys are tested, not declared, and the marts have enforced contracts | Declaring primary and foreign keys | Snowflake doesn't enforce them, so a declared key is just a comment. A failing test is a real signal. |
| D12 | `dim_customer` is one row per person (`customer_unique_id`), located by their first order | One row per `customer_id`; the latest location | `customer_id` is new on every order, so repeat purchase would look like 0%. 39 people span more than one state, so a rule was needed. |
| D13 | First order = the earliest purchase, ties broken by `order_id` | Leaving ties to chance | 276 people tie on their first timestamp, so the cohort could change between runs. |
| D14 | One review per order, the latest, plus a `review_count`; no review means NULL, never 0 | Averaging scores; keeping every review | The latest review is the customer's final word, and averaging invents scores. 547 orders have several reviews. |
| D15 | Payments roll up to one row per order before any join | Joining payments to items | Joining at item grain repeats rows: payments come out 26.9% too high, prices 4.5%. |
| D16 | Revenue = item price, without freight; `payment_total` is kept separately | Revenue from payments, or price plus freight | Only items link to a category, product or seller. Items and payments agree within 1.00 for 99.75% of orders. |
| D17 | Canceled and unavailable orders don't count as revenue; in-flight orders do | Counting everything; delivered orders only | That money was never collected. It's 467 orders and 0.72% of item value. |
| D18 | "Late" is compared as dates | Comparing full timestamps | Every estimated date is at midnight, so timestamps would flag 1,292 same-day deliveries: 7,826 late against 6,534 (6.77%). |
| D19 | Delivery measures use only delivered orders that have a delivery date | Every order with a date | A measure on an order that never arrived means nothing. 96,470 orders qualify. |
| D20 | Out-of-order timestamps are kept, not dropped | Dropping those rows | Dropping would change the order counts, and days to deliver (purchase to delivery) is never negative. 23 orders are affected. |
| D21 | `fct_orders` keeps orders with no items, payments or reviews | Inner joins that drop them | They're real orders: 775 have no items, 768 no review and 1 no payment. |
| D22 | Category: English name, else the Portuguese name, else `unknown` | `unknown` for anything untranslated | Keeps the information that exists. Only 2 categories (13 products) lack a translation. |
| D23 | A seller dimension is included | Leaving it out (the brief says it's optional) | The anomaly query needs a late rate per seller. |
| D24 | City and state stay on the address, a deliberate break from 3NF | A separate zip table | A zip prefix doesn't decide the city here: 39 customer prefixes map to several cities, and 17 seller prefixes to several states. |
| D25 | `dim_date` runs from 2016-01-01 to 2018-12-31, keyed on the date | Only the order dates; a surrogate key | Whole years cover the estimated dates, which run past the last purchase. A date is already a good key. |
| D26 | Odd values are kept and documented | Correcting or dropping them | Staging reports what the source said, for example 9 payments of 0.00 and 383 items with no freight. |
| D27 | Geolocation is left out | One row per zip prefix | The analysis works at state level, which customers and sellers already have. |
| D28 | No history (SCD2) snapshot | Snapshotting the dimensions | It's a static export, so history would show nothing. |
| D29 | Four intermediate models: items, payments and reviews rolled up per order, and each person's orders ranked | Doing it all inside `fct_orders` | Each roll-up fixes fan-out, and the ranking is shared by `dim_customer` and `fct_orders`. |
| D30 | No dbt packages; three small local helpers instead | Installing `dbt_utils` | A package is someone else's code to trust, and only three helpers were needed. Switching later means rebuilding the keys together. |
| D31 | Strict casts with an explicit timestamp format | `try_cast`, which turns bad values into NULL | A bad value should stop the build, not vanish. Every column parses today. |
| D32 | The three lineage columns go through staging; the marts drop them | Dropping them in staging | Any staged row can be traced back to its file and line. |
| D33 | No de-duplication in staging. **Superseded by D71.** | `qualify row_number() = 1` on every key | At the time no key repeated, and a quiet de-dup could hide a double load. |
| D34 | The type rules live in three macros | Repeating the casts in every model | Change a rule once and every model follows. |
| D35 | Tests follow the data: keys, relationships, accepted values, `not_null` only where there are no blanks; the untranslated products warn | `not_null` everywhere; failing on the 13 products | A test should catch a broken assumption. The 13 products are known and handled (D22), so they warn. |
| D36 | A test compares each staging model's row count with RAW's distinct keys | Key tests alone | A bad join or filter can lose rows and still leave the keys unique. |
| D37 | dbt runs from `dbt_project/` with a `profiles.yml` built from environment variables, always as `build --select` | A profile in the home folder; `dbt run`; running everything | No secrets to leak, tests run with the models, and a typo can't run the whole project. |
| D38 | Every mart has an enforced contract | Tests only | dbt refuses to build if a column or type drifts, so an analyst's query can't break quietly. |
| D39 | The first order counts whatever its status | The first revenue or delivered order | A canceled first order is still the first experience. 1,153 people had one. |
| D40 | `dim_date` is generated with Snowflake's `GENERATOR` | `dbt_utils.date_spine`; a seed file | Nine lines of SQL and no package. |
| D41 | Fact foreign keys are computed with the same hash macro, not looked up | Joining each dimension to fetch its key | A join can drop or repeat rows; recomputing can't. Relationship tests prove every key lands. |
| D42 | The key macro is `md5` of the values as text, with a NULL marker and a delimiter | `dbt_utils`; a sequence | The same keys after every rebuild, and no collisions between NULL and an empty string, or between `('ab','c')` and `('a','bc')`. |
| D43 | `primary_payment_type` is the largest payment, a tie going to the earlier one | The most frequent type; the first payment | The largest payment is how they mainly paid. 188 orders tie. |
| D44 | Day counts use `DATEDIFF(day, ...)` on dates | Hours divided by 24 | Matches D18, and customers think in days. |
| D45 | Mart checks in layers: keys, reconciliation, one first order per person, unit tests and golden numbers | Key tests alone | Each layer catches what the others miss. A deliberately bad join made four kinds of check fail. |
| D46 | "Came back" has two meanings: `has_multiple_orders` (any second order) and `repeat_after_first_delivery` (a later order after the first delivery). The analysis uses the second. | One flag for any second order | An order placed before the first one arrived isn't a reaction to it. The plain count overstates repeat about 1.6 times: 1,813 of 93,248 came back (1.94%), against 3.12%. |
| D47 | The `revenue` columns are already filtered; average order value divides by revenue orders with items | A flag every query has to remember | A bare `SUM(price)` gives 13.59M instead of 13.49M, and it's an easy mistake to make. |
| D48 | `is_revenue_order` and `is_late` are copied onto the item fact; a seller's late rate counts distinct orders | Joining the facts every time; counting units | One definition each. By order 6.77% are late, by unit 6.59%. |
| D49 | `installments_max` added to `fct_orders`, `used_voucher` removed | Keeping a column nothing used | An unused column is one more thing to defend. |
| D50 | A review of the marts changed D10, D30 and D46 to D49; richer customer columns, holiday flags and exposures were left out | Taking every suggestion | Each point was checked against the data first, and nothing left out answers one of the five questions. |
| D51 | Q2 covers 2017-01 to 2018-08 | Every month | The edges are thin (2016 has 329 orders; September and October 2018 have 16 and 4), so changes there would be noise. |
| D52 | Seller anomalies need 30 or more measurable orders, count distinct orders and show two z-scores | Scoring every seller | One late order swings a tiny seller's rate. 24 of the 627 scored sellers are flagged. |
| D53 | Q5 cohort: delivered first orders with 180 days of follow-up; "returned" means a later order within those 180 days | No window; 90 or 365 days | Without a window, later cohorts look worse just because they had less time. 180 days keeps most first deliveries and most returns. |
| D54 | Q4 gives each measure its own base and flags states with fewer than 100 delivered orders | One base for everything; dropping small states | A late rate should only count delivered orders. RR, AP and AC are flagged, not dropped. |
| D55 | Every analytics figure is recomputed from staging a second way | Trusting the marts' own tests | The checks cover the exact numbers the memo quotes. Two deliberate breaks were caught. |
| D56 | Insight 1 is checked inside each state and with the state mix held fixed | Only the overall gap | Late rates are highest far away, so geography could explain it. It doesn't: 1.6 to 2.3 stars in all 14 states, 1.92 adjusted. |
| D57 | Campaign segment: first order late or rated 1 or 2 stars | Late only; everyone | Both show a lower repeat rate, and together they're big enough to test (about 11,900 people a year). |
| D58 | Offer: an apology and free shipping capped at R$15 for 60 days; uplifts of 0.25, 0.5 and 1.0 points are stated as assumptions | Uncapped shipping; a percentage discount | The cap brings the average cost from R$23.03 to R$13.78. Nothing in the data says how people respond to a voucher, so the test has to measure it. |
| D59 | A 50/50 randomised holdout, measured on repeat orders within 8 weeks | 80/20; 90 days; before and after | The segment is small, so an 80/20 split leaves too small a holdout. A year of enrolment detects about 0.49 points. |
| D60 | Two production checks run today; the third (freshness and volume) is written down | Configuring freshness now | Payments differ from items for 0.25% of orders, so that check warns above 1%. A freshness rule on a one-off export would warn forever. |
| D61 | The README was tested by following it from a fresh clone | Trusting it | The first try hit Windows's 260-character path limit, which is now in the README. |
| D62 | The memo covers what was built, the value and the next step | Leading with the finding | That's what the brief asks for. It's 199 words. |
| D63 | The app is a separate Streamlit layer in `app/`, with built-in widgets and no custom HTML or CSS | Dash; a static page; a notebook | Light, Python only, and it doesn't touch the pipeline. |
| D64 | The app reads Snowflake live when it can, and a saved snapshot otherwise | Live only; an order-level extract | It runs without credentials. The snapshot is about 40 KB of aggregates with no customer or order IDs. |
| D65 | SQL is fixed strings and the voucher maths runs in Python | A query per slider | No user input reaches SQL, and a test checks the app matches the write-up. |
| D66 | One colour per idea, bars from zero, legends above the plot | The default palette; a truncated axis | A bar's length should mean the quantity. |
| D67 | `pyarrow` pinned to 21.0.0 | The newest release | 26.0.1 was blocked by Windows Application Control on this machine. |
| D68 | The app was tested in a browser at desktop and phone width; 30 automated checks keep the fixes | Only reading the code | Layout bugs only show up when the page renders. Seven were found and fixed. |
| D69 | A security review found nothing serious; the app listens on 127.0.0.1 and `secrets.toml` is ignored in every folder | Dropping the web font; a read-only role now | The font is a look choice for a local demo, and the README says to use a read-only role for live data. |
| D70 | No language-model feature is built; classifying review comments by complaint reason is proposed, not run | Natural-language querying; memo drafting | It's the only option tied to a finding. Cortex availability in this region wasn't checked, so it isn't claimed as working. |
| D71 | Staging keeps one row per key (the newest load wins), and a warning test, `raw_keys_are_unique`, reports any repeat in RAW. Supersedes D33. | No de-duplication | The brief lists de-duplication as a staging job, and the warning test means a double load can't hide. It removes nothing today. |
| D72 | The README's build command names `raw_keys_are_unique` | Changing the expected result to 175 | No layer selector picks that test up, so the old command gave PASS=175, not 176. |
| D73 | Revenue, late rate, repeat rate and a few more are defined once as a semantic layer in `_marts__semantic.yml` | Leaving them in the columns only | One name per business word for every tool. It changes no table, and the app doesn't use it yet. |
