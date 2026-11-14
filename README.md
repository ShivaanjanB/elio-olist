# Olist commerce pipeline: Snowflake + dbt

Raw Olist CSVs → Snowflake `RAW` → dbt staging (normalised) → marts (star schema) → analytics → one commercial recommendation.

This repository loads the Brazilian Olist e-commerce dataset into Snowflake, models it in dbt, answers five business questions in
SQL, and recommends one measurable campaign. **Start with [`analysis_answers.md`](analysis_answers.md)** for the findings, the
recommendation and the client memo. The rest of this file is how to reproduce everything.

**In one paragraph.** Almost nobody comes back: 96.9% of customers buy once, and only 1.8% reorder within six months. Late
delivery wrecks reviews (2.27 stars against 4.29), and customers whose first order went badly return less. The recommendation is a
capped, randomised voucher test on about 11,900 such customers a year, sized honestly: the prize is small, so the point is to learn
what a voucher does before spending more.

## Platform and why

**Snowflake**, with transformations in **dbt Core** (`dbt-snowflake`). Snowflake is the brief's default, and it keeps the load
(`PUT` and `COPY INTO`), the transformations and the analytics in one place. dbt Core was chosen over dbt Cloud because it needs no
second account and runs from a pinned `requirements.txt`.

## Setup used

| | |
|---|---|
| Snowflake account | 30-day trial, **Standard edition**, AWS EU (London). Server version 10.41.101 |
| Warehouse | `ELIO_WH`, **X-Small**, auto-suspend 60 seconds, created suspended |
| Resource monitor | `ELIO_MONITOR`: 20 credits a month, notifies at 75%, suspends at 100% |
| Database | `ELIO_OLIST` |
| Schemas | `RAW`, `STAGING`, `INTERMEDIATE`, `MARTS` (a `generate_schema_name` override makes dbt use these exact names) |
| Roles and user | `ELIO_TRANSFORMER` does all the work with least privilege. `ELIO_SVC` is a service user with no password: it signs in only with an RSA key pair. Account setup is run once as `ACCOUNTADMIN` |
| Python | 3.13 |
| dbt-core, dbt-snowflake, snowflake-connector-python | 1.12.7, 1.12.5, 5.2.0 (pinned in `requirements.txt`) |
| Local OS | Windows 11, PowerShell. On macOS or Linux the same scripts run; only the environment-loading line differs (see [`.env.example`](.env.example)) |

## Reproduce it end to end

From a PowerShell prompt. You need a Snowflake trial account, Python 3.13, Git (its `openssl` is used to make the key) and the
[Olist dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

**1. Install.**

```powershell
git clone https://github.com/ShivaanjanB/elio-olist.git
cd elio-olist
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

On Windows, clone into a short folder (for example `C:\src\elio-olist`): in a deeply nested folder `pip` can hit Windows's
260-character path limit unless long paths are enabled. `pip` may also print a warning about an optional extra
(`secure-local-storage`), which is harmless.

**2. One-off manual setup** (these need a person, so they are not scripted). The details are in
[`ingest/README.md`](ingest/README.md#one-off-manual-steps):

1. Generate the service user's key pair: `.\scripts\new_keypair.ps1` (the private key stays outside the repo).
2. In a Snowsight worksheet as `ACCOUNTADMIN`, run [`ingest/00_setup_account.sql`](ingest/00_setup_account.sql) with the public key
   pasted in. It creates the role, warehouse, database, schema, resource monitor and service user.
3. Copy `.env.example` to `.env` and fill it in (account, user, key path, role, warehouse, database). It is git-ignored.
4. Unzip the nine Kaggle CSVs into `data/raw/` (git-ignored). Geolocation is downloaded but not loaded (decision D27).

**3. Load the raw files.** Run steps 3 to 5 in the same PowerShell window, from the repo root, because they share the
environment variables and the `$py` variable. Every step is safe to repeat. The full explanation, the load
notes and the rebuild path are in [`ingest/README.md`](ingest/README.md) and [`ingest/LOAD_NOTES.md`](ingest/LOAD_NOTES.md).

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

**4. Build the dbt project.** `profiles.yml` is built entirely from the same environment variables, so it holds no secrets.

```powershell
Copy-Item dbt_project\profiles.yml.example dbt_project\profiles.yml
cd dbt_project
..\.venv\Scripts\dbt.exe deps          # there are no packages (D30), so this only confirms that
..\.venv\Scripts\dbt.exe debug         # connection check
..\.venv\Scripts\dbt.exe build --select staging intermediate marts
cd ..
```

Expected: `PASS=173 WARN=1 ERROR=0` (174 checks: 6 unit tests, data tests and singular tests). The one warning is deliberate: 13
products belong to 2 categories with no English translation (decision D22), and it is a `warn` test so it stays visible without
failing the build. Always pass `--select`; `build` runs models and tests together, so a model that builds but fails its tests is
never treated as done.

**5. Run the analytics queries.** Each file prints its results; the `checks` files recompute every figure from staging, and every
`ok` must be `True`.

```powershell
& $py ingest\run_sql.py sql\analytics_queries.sql     # Q1 to Q5: categories, monthly trend, anomalies, states, repeat rate
& $py ingest\run_sql.py sql\analytics_checks.sql      # independent cross-check of those figures
& $py ingest\run_sql.py sql\insight_queries.sql       # review score by lateness, repeat rates, campaign sizing
& $py ingest\run_sql.py sql\insight_checks.sql        # independent cross-check of those figures
& $py ingest\run_sql.py docs\mart_checks.sql          # sanity queries on the marts, each saying what it should show
```

Every statement uses fully qualified names, so any of them also runs on its own in Snowsight.

**Checked from a fresh clone.** The steps above were run from a new clone with a new virtual environment (steps 3 to 5, against
the account that was already set up). Every command succeeded, `dbt build` took about 35 seconds and gave
`PASS=173 WARN=1 ERROR=0`, and every `ok` in the two cross-check files was `True`.

## How the pipeline is built

| Layer | Schema | Materialised as | Why |
|---|---|---|---|
| Raw | `RAW` | Tables, filled by `COPY INTO` | The files exactly as received (all `VARCHAR`), plus the source file, row number and load time of every row. Never edited |
| Staging | `STAGING` | Views | One model per raw table: typed, renamed and normalised to third normal form. Cheap, always current, and a failed test points at one source |
| Intermediate | `INTERMEDIATE` | Views | Rolls each child table up to one row per order, the fix for fan-out, and ranks each person's orders. Views stay queryable while debugging |
| Marts | `MARTS` | Tables | The star schema: `fct_orders`, `fct_order_items`, `dim_customer`, `dim_product`, `dim_seller`, `dim_date`. Analysts hit these, so the join cost is paid once |

Snowflake does not enforce keys, so every key is proved with a dbt test, and every mart has an enforced contract (names and types
declared, and dbt refuses to build if they differ). 70 decisions, each with the alternatives, the reason and the evidence, are in
[`docs/decision_log.md`](docs/decision_log.md). The entity-relationship diagram, normalisation argument and star schema are in
[`docs/data_model.md`](docs/data_model.md).

## Explore the results (optional app)

A small Streamlit app in [`app/`](app/) lets you click through the three findings instead of reading them: late deliveries and
review scores, how late first orders affect coming back, and a calculator for the voucher test (what it could earn, and whether a
test of a given length could see it). It needs no credentials: it reads a saved snapshot of the mart results
(`app/snapshot/snapshot.json`, about 40 KB of aggregates with no customer or order identifiers).

```powershell
.\.venv\Scripts\python.exe -m pip install -r app\requirements.txt
cd app
..\.venv\Scripts\streamlit.exe run streamlit_app.py
```

It opens at `http://127.0.0.1:8501` and listens on this machine only. Run it from the `app` folder so it finds `.streamlit\config.toml`.

- **Live data.** With the Snowflake variables loaded (`. .\scripts\load_env.ps1`) the app reads the marts directly and refreshes
  hourly. If Snowflake cannot be reached it falls back to the snapshot and says so in the sidebar. Set `OLIST_APP_SOURCE=snapshot`
  to force the snapshot.
- **Refresh the snapshot** after the marts change: `cd app; ..\.venv\Scripts\python.exe make_snapshot.py`.
- **Tests.** `cd app; ..\.venv\Scripts\python.exe -m unittest discover -s tests` runs 30 checks: the calculator reproduces the
  scenario table in `analysis_answers.md`, every page loads and every widget works at its limits, and the snapshot is the one the
  write-up quotes. They need no network.
- **Safe to run.** Every SQL statement is a fixed string in `app/olist_app/queries.py` (widgets never reach a query), nothing is
  rendered as raw HTML, and error text is never shown on the page. For live data prefer a role that can only `SELECT` from
  `ELIO_OLIST.MARTS`; the pipeline's `ELIO_TRANSFORMER` can do much more than the app needs.

## Repo layout

| Path | Contents |
|---|---|
| `ingest/` | Account setup SQL, file format, stage, raw tables, load and reconcile scripts, and the load notes. See [`ingest/README.md`](ingest/README.md) |
| `scripts/` | `new_keypair.ps1`, `load_env.ps1` and `test_connection.py` |
| `app/` | The optional Streamlit explorer: three pages (`app_pages/`), the voucher calculator (`olist_app/calculator.py`), fixed SQL, a saved snapshot of the results and tests |
| `dbt_project/` | The dbt project. `models/staging`, `models/intermediate`, `models/marts` (SQL, descriptions, tests and contracts), `macros/`, `tests/` (generic and singular), `profiles.yml.example`, `packages.yml` |
| `docs/data_model.md` | ERD, normalisation reasoning, keys, types, the star schema and the metric definitions |
| `docs/decision_log.md` | Every design decision |
| `docs/analytics_results.md` | The analytics results and how to read them |
| `docs/*_checks.sql` | The evidence queries behind the model design, and sanity queries on the marts |
| `sql/analytics_queries.sql` | The five analytics queries (Q1 to Q5) |
| `sql/insight_queries.sql` | The queries behind the insights and the campaign sizing |
| `sql/*_checks.sql` | Independent recomputation of each headline figure from staging |
| `analysis_answers.md` | B1 to B5: insights, recommendation, caveats and production checks, the client memo, and the LLM proposal |
| `requirements.txt`, `.env.example`, `.gitignore` | Pinned dependencies, the environment template, and what is kept out of git (credentials, `profiles.yml`, `target/`, `logs/`, data) |
| `data/raw/` | The Olist CSVs from Kaggle. Not committed |

## Assumptions, shortcuts and what I would do next

Assumptions about the data and the analysis, with the evidence for each, are in the decision log. The ones to know:

- **Timestamps have no time zone** in the source and are kept as `TIMESTAMP_NTZ`, with Brazil local time assumed (D09). Delivery and lateness are measured in whole days, so the effect is small.
- **"Late" is measured as dates** against the promised date, because every promised date is at midnight (D18): 6.77% of delivered orders, against 8.1% if compared as timestamps.
- **The campaign uplifts are assumptions**, and revenue is item revenue, not profit, because the data has no margin. Only the test can measure the effect (`analysis_answers.md`).

Shortcuts taken for the time limit:

- **No dbt packages.** The composite-key test, surrogate-key macro and date spine are short local code (D30). `dbt_utils` would replace them in a line each.
- **The service user's private key is unencrypted on disk,** which is acceptable for a trial account.
- **One environment.** There is no separate dev and production, and no CI.
- **No incremental models, no history table and no freshness check.** The data is a one-off export, so a snapshot would show nothing (D28) and a freshness rule would go stale by design (D60).

What I would do next, in order:

1. **CI:** a GitHub Actions workflow that runs `dbt build` on each pull request into a CI schema, using credentials stored as secrets, with a zero-copy clone of production for a realistic test environment.
2. **Dev and production separation:** separate databases or schemas with their own roles and warehouses.
3. **Incremental `fct_orders`** with a merge strategy and a lookback window, because orders change status after they are loaded, so an increment keyed on purchase date would be wrong. Add the freshness and row-volume checks when loading is scheduled.
4. **Run the holdout test** described in `analysis_answers.md`, and size the delivery-promise fallback.
5. **A review-comment classifier** (Snowflake Cortex) to tag complaints as delivery, product or wrong item.

## Working method

The work was done on feature branches with one pull request per phase (ingest, data model, staging, marts, analytics, insights,
packaging), each merged with a merge commit, so the history reads as the order the work was done in.
