# Olist commerce pipeline: Snowflake + dbt

Raw Olist CSVs → Snowflake `RAW` → dbt staging → star-schema marts → analytics → one recommendation.

This is a take-home project. It loads the Brazilian Olist e-commerce dataset into Snowflake, models it in dbt, answers five business
questions in SQL, and ends with one recommendation: a small, capped voucher test. If you only read one thing, make it
[`analysis_answers.md`](analysis_answers.md). It has the findings, the recommendation and the client memo. The rest of this file
is about how it's built and how to run it.

**The short version.** Almost nobody comes back. 96.9% of customers buy once, and only 1.8% order again within six months. Late
deliveries hammer the reviews (2.27 stars against 4.29 for on-time orders), and people whose first order goes badly come back
less. So I'm recommending a randomised voucher test, capped in cost, on about 11,900 of those customers a year. The prize is
small. The point is to find out whether a voucher does anything before anyone spends more on it.

**A heads-up on running it.** To run this end to end you need your own Snowflake trial and the Kaggle files, so I don't expect
anyone to. I've written the steps down anyway so it can be checked. Everything it produces is also written out in
`analysis_answers.md`, and the app (further down) runs from a saved snapshot with no login at all.

## Platform and why

Snowflake is the brief's default, and it lets the load (`PUT` and `COPY INTO`), the transformations and the analytics all live in
one place. I went with dbt Core over dbt Cloud because it needs no second account and runs from a pinned `requirements.txt`.

## Setup used

| | |
|---|---|
| Snowflake account | 30-day trial, **Standard edition**, AWS EU (London). Server version 10.41.101 |
| Warehouse | `ELIO_WH`, **X-Small**, auto-suspend after 60 seconds, created suspended |
| Resource monitor | `ELIO_MONITOR`: 20 credits a month, notifies at 75%, suspends at 100% |
| Database | `ELIO_OLIST` |
| Schemas | `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS` (a `generate_schema_name` override makes dbt use exactly these names) |
| Roles and user | `ELIO_TRANSFORMER` does all the work, with least privilege. `ELIO_SVC` is a service user with no password: it signs in with an RSA key pair only. Account setup runs once as `ACCOUNTADMIN` |
| Python | 3.13 |
| dbt-core, dbt-snowflake, snowflake-connector-python | 1.12.7, 1.12.5, 5.2.0 (pinned in `requirements.txt`) |
| Local OS | Windows 11, PowerShell. The scripts should run on macOS or Linux too; only the line that loads the environment differs (see [`.env.example`](.env.example)) |

## Running it end to end

You'll need a Snowflake trial account, Python 3.13, Git (I use its `openssl` to make the key) and the
[Olist dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce). Everything below is from a PowerShell prompt.

**1. Install.**

```powershell
git clone https://github.com/ShivaanjanB/elio-olist.git
cd elio-olist
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

On Windows, clone into a short folder like `C:\src\elio-olist`. In a deeply nested folder `pip` can hit Windows's 260-character
path limit unless long paths are switched on. `pip` might also print a warning about an optional extra (`secure-local-storage`).
It's harmless.

**2. A few things to do by hand, once.** These need a person, so they aren't scripted. The details are in
[`ingest/README.md`](ingest/README.md#one-off-manual-steps):

1. Generate the service user's key pair with `.\scripts\new_keypair.ps1`. The private key stays outside the repo.
2. In a Snowsight worksheet, as `ACCOUNTADMIN`, run [`ingest/00_setup_account.sql`](ingest/00_setup_account.sql) with the public key
   pasted in. It creates the role, warehouse, database, schema, resource monitor and service user.
3. Copy `.env.example` to `.env` and fill it in (account, user, key path, role, warehouse, database). It's git-ignored.
4. Unzip the nine Kaggle CSVs into `data/raw/` (also git-ignored). Geolocation gets downloaded but not loaded (decision D27).

**3. Load the raw files.** Run steps 3 to 5 in the same PowerShell window, from the repo root, since they share the environment
variables and the `$py` variable. Everything is safe to re-run. There's more detail, including how to rebuild `RAW`, in
[`ingest/README.md`](ingest/README.md) and [`ingest/LOAD_NOTES.md`](ingest/LOAD_NOTES.md).

```powershell
. .\scripts\load_env.ps1                                         # load .env into this shell
$py = ".\.venv\Scripts\python.exe"
& $py scripts\test_connection.py                                 # a successful sign-in as ELIO_SVC
& $py ingest\run_sql.py ingest\01_file_format.sql                # CSV file format
& $py ingest\run_sql.py ingest\02_stage.sql                      # internal stage
& $py ingest\02_upload_files.py                                  # PUT the eight CSVs
& $py ingest\run_sql.py ingest\03_raw_tables.sql                 # eight RAW tables, all VARCHAR plus lineage columns
& $py ingest\04_dry_run.py                                       # must show 0 error rows
& $py ingest\run_sql.py ingest\04_load.sql                       # COPY INTO, ON_ERROR = ABORT_STATEMENT
& $py ingest\05_reconcile.py                                     # row counts must reconcile for every table
```

**4. Build the dbt project.** `profiles.yml` is built from the same environment variables, so there are no secrets in it.

```powershell
Copy-Item dbt_project\profiles.yml.example dbt_project\profiles.yml
cd dbt_project
..\.venv\Scripts\dbt.exe deps          # there are no packages (D30), so this only confirms that
..\.venv\Scripts\dbt.exe debug         # connection check
..\.venv\Scripts\dbt.exe build --select staging intermediate marts raw_keys_are_unique
cd ..
```

You should end up with `PASS=176 WARN=1 ERROR=0` (177 checks: 18 models, 8 unit tests, and the data and singular tests).
`raw_keys_are_unique` is named explicitly because it only reads the `RAW` tables, so none of the layer selectors pick it up. Leave
it off and you get `PASS=175 WARN=1`. The one warning is on purpose: 13 products sit in 2 categories that have no English
translation (decision D22). It's a `warn` test, so it stays visible without failing the build. Always pass `--select`. `build` runs
models and tests together, so a model that builds but fails its tests never counts as done.

**5. Run the analytics queries.** Each file prints its results. The `checks` files recompute every figure from staging a second
way, and every `ok` should be `True`.

```powershell
& $py ingest\run_sql.py sql\analytics_queries.sql     # Q1 to Q5: categories, monthly trend, anomalies, states, repeat rate
& $py ingest\run_sql.py sql\analytics_checks.sql      # independent cross-check of those figures
& $py ingest\run_sql.py sql\insight_queries.sql       # review score by lateness, repeat rates, campaign sizing
& $py ingest\run_sql.py sql\insight_checks.sql        # independent cross-check of those figures
& $py ingest\run_sql.py docs\mart_checks.sql          # sanity queries on the marts, each saying what it should show
```

Every statement uses fully qualified names, so any of them also runs on its own in Snowsight.

**Did it work from a clean start?** I ran steps 3 to 5 from a fresh clone with a new virtual environment, against the account that
was already set up. Every command worked, `dbt build` took about 35 seconds and gave `PASS=173 WARN=1 ERROR=0` (it's 176 now that
staging de-duplicates, D71), and every `ok` in the two cross-check files was `True`.

## How the pipeline is built

| Layer | Schema | Built as | What it does |
|---|---|---|---|
| Raw | `RAW` | Tables, filled by `COPY INTO` | The files exactly as they arrived (all `VARCHAR`), plus the source file, row number and load time on every row. Never edited |
| Staging | `STAGING` | Views | One model per raw table. Types fixed, columns renamed, one row per key (newest load wins), normalised to third normal form. Views are cheap and always current, and a failed test points at one source |
| Intermediate | `INTERMEDIATE` | Views | Rolls each child table up to one row per order so a join can't duplicate orders (the fan-out problem), and ranks each person's orders. Views, so they're easy to query while debugging |
| Marts | `MARTS` | Tables | The star schema: `fct_orders`, `fct_order_items`, `dim_customer`, `dim_product`, `dim_seller`, `dim_date`. Tables, because analysts query these and the join cost gets paid once |

Snowflake doesn't enforce keys, so every key has a dbt test, and every mart has an enforced contract (the columns and types are
declared, and dbt refuses to build if they drift). There are 73 decisions in [`docs/decision_log.md`](docs/decision_log.md), each
with what I picked it over and why. The ER diagram, the normalisation reasoning and the
star schema are in [`docs/data_model.md`](docs/data_model.md).

I've also defined the main business words (revenue, orders, average order value, late delivery rate, average review score, repeat
rate) once, as a semantic layer in [`_marts__semantic.yml`](dbt_project/models/marts/_marts__semantic.yml) (D73). It doesn't change
any table, and [`docs/semantic_layer_checks.sql`](docs/semantic_layer_checks.sql) recomputes each metric in plain SQL as a check. The
app doesn't read it yet.

## Explore the results (optional app)

There's a small Streamlit app in [`app/`](app/) if you'd rather click around than read. It has three pages: late deliveries and
review scores, how a late first order affects coming back, and a calculator for the voucher test (what it could earn, and whether a
test of a given length could even see it). It needs no credentials. It reads a saved snapshot of the mart results
(`app/snapshot/snapshot.json`, about 40 KB of aggregates with no customer or order identifiers).

```powershell
.\.venv\Scripts\python.exe -m pip install -r app\requirements.txt
cd app
..\.venv\Scripts\streamlit.exe run streamlit_app.py
```

It opens at `http://127.0.0.1:8501` and only listens on this machine. Run it from the `app` folder so it finds `.streamlit\config.toml`.

- **Live data.** With the Snowflake variables loaded (`. .\scripts\load_env.ps1`), the app reads the marts directly and refreshes
  hourly. If it can't reach Snowflake it falls back to the snapshot and says so in the sidebar. Set `OLIST_APP_SOURCE=snapshot`
  to force the snapshot.
- **Refreshing the snapshot** after the marts change: `cd app; ..\.venv\Scripts\python.exe make_snapshot.py`.
- **Tests.** `cd app; ..\.venv\Scripts\python.exe -m unittest discover -s tests` runs 30 checks. The calculator reproduces the
  scenario table in `analysis_answers.md`, every page loads, every widget works at its limits, and the snapshot is the one the
  write-up quotes. They don't need a network.
- **Safety.** Every SQL statement is a fixed string in `app/olist_app/queries.py` (widgets never reach a query), nothing is
  rendered as raw HTML, and error text never shows on the page. If you use live data, give it a role that can only `SELECT` from
  `ELIO_OLIST.MARTS`. The pipeline's `ELIO_TRANSFORMER` can do a lot more than the app needs.

## Repo layout

| Path | What's in it |
|---|---|
| `ingest/` | Account setup SQL, file format, stage, raw tables, the load and reconcile scripts, and the load notes. See [`ingest/README.md`](ingest/README.md) |
| `scripts/` | `new_keypair.ps1`, `load_env.ps1` and `test_connection.py` |
| `app/` | The optional Streamlit explorer: three pages (`app_pages/`), the voucher calculator (`olist_app/calculator.py`), fixed SQL, a saved snapshot of the results, and tests |
| `dbt_project/` | The dbt project. `models/staging`, `models/intermediate` and `models/marts` (SQL, descriptions, tests and contracts), `macros/`, `tests/` (generic and singular), `profiles.yml.example`, `packages.yml` |
| `docs/data_model.md` | ER diagram, normalisation reasoning, keys, types, the star schema and the metric definitions |
| `docs/decision_log.md` | Every design decision |
| `docs/analytics_results.md` | The analytics results and how to read them |
| `docs/*_checks.sql` | The evidence queries behind the model design, and sanity queries on the marts |
| `sql/analytics_queries.sql` | The five analytics queries (Q1 to Q5) |
| `sql/insight_queries.sql` | The queries behind the insights and the campaign sizing |
| `sql/*_checks.sql` | Independent recomputation of each headline figure from staging |
| `analysis_answers.md` | B1 to B5: insights, recommendation, caveats and production checks, the client memo, and the LLM proposal |
| `requirements.txt`, `.env.example`, `.gitignore` | Pinned dependencies, the environment template, and what's kept out of git (credentials, `profiles.yml`, `target/`, `logs/`, data) |
| `data/raw/` | The Olist CSVs from Kaggle. Not committed |

## Assumptions, shortcuts and what I would do next

The assumptions about the data and the analysis, with the evidence, are in the decision log. These are the ones worth knowing:

- **The source timestamps have no time zone.** I kept them as `TIMESTAMP_NTZ` and assumed Brazil local time (D09). Delivery and lateness are counted in whole days, so it barely matters.
- **"Late" is measured by date** against the promised date, because every promised date sits at midnight (D18). That gives 6.77% of delivered orders. Comparing timestamps instead would give 8.1%.
- **The voucher uplifts are assumptions,** and revenue means item revenue, not profit, because there's no margin in the data. Only the test itself can measure the real effect (see `analysis_answers.md`).

Shortcuts I took because of the time limit:

- **No dbt packages.** The composite-key test, the surrogate-key macro and the date spine are short bits of local code (D30). `dbt_utils` would do each in a line.
- **The service user's private key sits unencrypted on disk.** Fine for a trial account, not for anything real.
- **One environment.** There's no separate dev and prod, and no CI.
- **No incremental models, no history table, no freshness check.** The data is a one-off export, so a snapshot would show nothing (D28) and a freshness rule would go stale by design (D60).

What I'd do next, in order:

1. **CI.** A GitHub Actions workflow that runs `dbt build` on each pull request into a CI schema, with credentials stored as secrets and a zero-copy clone of production as the test environment.
2. **Dev and production separation.** Separate databases or schemas, each with its own roles and warehouses.
3. **An incremental `fct_orders`** with a merge strategy and a lookback window. Orders change status after they're loaded, so an increment keyed on purchase date would get it wrong. The freshness and row-volume checks would go in when loading gets scheduled.
4. **Run the holdout test** described in `analysis_answers.md`, and size the delivery-promise fallback.
5. **A review-comment classifier** (Snowflake Cortex) to tag complaints as delivery, product or wrong item.

## How I worked

I worked on feature branches with one pull request per phase (ingest, data model, staging, marts, analytics, insights, packaging),
each merged with a merge commit, so the history reads in the order the work happened. The app, the answers file, a staging
de-duplication change, a memo fix and the semantic layer each got their own pull request after that.
