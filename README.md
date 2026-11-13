# Olist commerce pipeline: Snowflake + dbt

Raw Olist CSVs → Snowflake `RAW` → dbt staging (normalised) → marts (star schema) → analytics → one commercial recommendation.

> Work in progress. Full setup and run instructions are added as each layer lands.

## Repo layout

| Path | Contents |
|---|---|
| `ingest/` | Snowflake account setup, file format, stage and `COPY INTO` scripts, plus load notes |
| `dbt_project/` | dbt sources, staging, intermediate and marts models with tests and docs |
| `docs/data_model.md` | ERD and normalisation reasoning |
| `sql/analytics_queries.sql` | Analytics queries run against the marts |
| `analysis_answers.md` | Insights, recommendation and client memo |
| `data/raw/` | Olist CSVs from Kaggle (not committed) |
| `docs/decision_log.md` | Every design decision, with the alternatives, the reason and the evidence |

## Run dbt

Needs the ingest to have been run first, so the `RAW` tables exist (see [`ingest/README.md`](ingest/README.md#run-order)).

From the repo root, in PowerShell:

```powershell
. .\scripts\load_env.ps1                               # the same settings the ingest scripts use
cd dbt_project
Copy-Item profiles.yml.example profiles.yml            # once; git-ignored, holds no secrets (values come from the environment)
..\.venv\Scripts\dbt.exe debug                         # connection check
..\.venv\Scripts\dbt.exe build --select staging intermediate marts   # builds 8 + 4 views and 6 tables, runs every test
```

Expected: `PASS=172 WARN=1 ERROR=0` (173 checks: 6 unit tests, the data tests and the singular tests). The one warning is
deliberate: 13 products belong to 2 categories with no English translation (decision D22), and it is a `warn` test so it stays
visible without failing the build.

To look at the numbers yourself after a build, run the sanity queries, which say what each result should be:

```powershell
cd ..
.\.venv\Scripts\python.exe ingest\run_sql.py docs\mart_checks.sql
```

Always pass `--select`; `build` runs models and tests together (a model that builds but fails its tests is not done).
