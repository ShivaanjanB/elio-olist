# Ingest: Olist CSVs into Snowflake `RAW`

## One-off manual steps

### 1. Generate a key pair for the service user
The pipeline signs in as `ELIO_SVC`, a Snowflake service user with no password. It only authenticates with an RSA key, and the private key stays outside the repo.

From the repo root, in PowerShell (it needs `openssl`, which comes with Git for Windows):

```powershell
.\scripts\new_keypair.ps1
```

The script writes `rsa_key.p8` (private) and `rsa_key.pub` (public) to `~\.snowflake\elio\` and locks the private key down to your Windows account. It then prints the public key on one line (paste that into `00_setup_account.sql`) and its SHA-256 fingerprint (compare it with Snowflake's `RSA_PUBLIC_KEY_FP`). It won't overwrite an existing key unless you pass `-Force`.

The private key isn't encrypted on disk. That's fine for a trial account. In production I'd encrypt it or keep it in a secrets manager.

### 2. Run the account setup
1. Open a Snowsight worksheet and switch the role to `ACCOUNTADMIN`.
2. Paste in [`00_setup_account.sql`](00_setup_account.sql).
3. Replace `<PASTE_ONE_LINE_PUBLIC_KEY_HERE>` with the one-line key.
4. Run all the statements.

The last one, `DESC USER ELIO_SVC`, should show `RSA_PUBLIC_KEY_FP = SHA256:…`.

### 3. Point local tools at the account
Copy `.env.example` to `.env` and fill it in. Then load it into your shell:
- Windows: `. .\scripts\load_env.ps1`
- macOS/Linux: `set -a; . ./.env; set +a`

### 4. Download the data
Download the Olist dataset from Kaggle and unzip the nine CSVs into `data/raw/`. The folder is git-ignored. Geolocation gets downloaded but not loaded.

## Run order
From the repo root in PowerShell, after `. .\scripts\load_env.ps1`. `py` below means `.\.venv\Scripts\python.exe`. Every Snowflake step runs as the service user `ELIO_SVC` with role `ELIO_TRANSFORMER`.

| # | Command | What it does |
|---|---|---|
| 1 | `py ingest\run_sql.py ingest\01_file_format.sql` | Creates the file format `RAW.OLIST_CSV` |
| 2 | `py ingest\run_sql.py ingest\02_stage.sql` | Creates the internal stage `RAW.OLIST_STAGE` (with a directory table) |
| 3 | `py ingest\02_upload_files.py` | `PUT`s the eight CSVs to the stage (`OVERWRITE=FALSE`, so it's safe to repeat) |
| 4 | `py ingest\run_sql.py ingest\02_check_staged_files.sql` | Reads the staged files through the format and reports record counts, line endings, accents and the byte-order mark |
| 5 | `py ingest\run_sql.py ingest\03_raw_tables.sql` | Creates the eight RAW tables (`IF NOT EXISTS`) |
| 6 | `py ingest\03_check_raw_tables.py` | Checks each table's columns against its CSV header |
| 7 | `py ingest\04_dry_run.py` | Dry run of every file with `VALIDATION_MODE`. It must show 0 error rows |
| 8 | `py ingest\run_sql.py ingest\04_load.sql` | Loads the tables, one `COPY INTO` each, with `ON_ERROR = ABORT_STATEMENT` |
| 9 | `py ingest\05_reconcile.py` | Four-way row-count reconciliation. It must show OK for every table |
| 10 | `py ingest\run_sql.py ingest\05_check_loaded_data.sql` | Checks the loaded data: blanks, zip prefixes, accents, line endings, profile facts |

**Rebuilding RAW from the staged files:** run `ingest\truncate_raw_tables.sql` through `run_sql.py`, then steps 7 to 9. Running step 8 again *without* truncating loads nothing, because Snowflake remembers which files it already loaded.

Findings, decisions and assumptions are in [LOAD_NOTES.md](LOAD_NOTES.md).

## Pinned versions
| Tool | Version |
|---|---|
| Python | 3.13.15 |
| dbt-core | 1.12.7 (pinned in `requirements.txt`) |
| dbt-snowflake | 1.12.5 (pinned in `requirements.txt`) |
| snowflake-connector-python | 5.2.0 (pinned in `requirements.txt`) |
| Snowflake (server, reported at sign-in) | 10.41.101 |
| openssl (key generation, from Git for Windows) | 3.5.7 |
| Git | 2.55.0 |
| Operating system | Windows 11 (build 10.0.26200) |

Install with `pip install -r requirements.txt` in a fresh virtual environment.

## What the files look like before loading
Before loading anything I profiled the raw CSVs with `python ingest/profile_csvs.py data/raw` (standard library only):

| File | Records | What stands out |
|---|---:|---|
| `olist_orders_dataset.csv` | 99,441 | 8 statuses (96,478 `delivered`); 2,965 blank customer-delivery dates; 160 blank approval times |
| `olist_order_items_dataset.csv` | 112,650 | One row per unit; `(order_id, order_item_id)` is unique |
| `olist_customers_dataset.csv` | 99,441 | `customer_id` is unique per order; only 96,096 distinct `customer_unique_id` (2,997 people appear more than once) |
| `olist_order_payments_dataset.csv` | 103,886 | `(order_id, payment_sequential)` is unique; 3 rows have `payment_type = not_defined` |
| `olist_order_reviews_dataset.csv` | 99,224 | Windows (CRLF) line endings; 3,852 comments contain line breaks, so the file has 104,720 physical lines; `review_id` repeats (789 ids) and 547 orders have more than one review; `(review_id, order_id)` is unique |
| `olist_products_dataset.csv` | 32,951 | 610 products with blank category and descriptive fields; misspelt `*_lenght` headers |
| `olist_sellers_dataset.csv` | 3,095 | Clean |
| `product_category_name_translation.csv` | 71 | Starts with a UTF-8 byte-order mark; CRLF line endings |
| `olist_geolocation_dataset.csv` | 1,000,163 | Only 19,015 zip prefixes, many rows each; **not loaded** (see below) |

Across all the files:
- **Encoding:** every file is valid UTF-8. Accented Portuguese text shows up in reviews, geolocation, sellers and the category translation. Customer city names are ASCII-only.
- **Zip prefixes:** always 5 characters with leading zeros (for example `01151`), so they have to stay text.
- **Quoting:** inconsistent. Some IDs are quoted and some aren't, even within one row.
- **Timestamps:** `YYYY-MM-DD HH24:MI:SS`, no time zone.

**Why geolocation is skipped:** the analysis works at state level, and `customers` and `sellers` already carry the state. Geolocation would only add map coordinates, and using it would mean first collapsing a million rows to one per zip prefix.
