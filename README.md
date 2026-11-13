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
