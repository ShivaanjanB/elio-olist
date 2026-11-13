# Load notes: Olist CSVs into Snowflake `RAW`

Run on 2026-11-13. Everything in this folder was run in the order given in [README.md](README.md#run-order); this file records **what I decided, what I found and what I assumed**.

## Summary

- Eight of the nine CSVs are loaded as-is into `ELIO_OLIST.RAW`, one table each. Geolocation is deliberately not loaded.
- Every table has the CSV's columns, in the CSV's order, all `VARCHAR`, plus three label columns: `_source_file`, `_source_row`, `_loaded_at`.
- **No rows failed to load, and none were dropped.** For every table, four independent counts agree: records in the CSV file, records readable from the staged file, rows `COPY` loaded, and rows in the table.
- Bad-row policy: `ON_ERROR = ABORT_STATEMENT`, backed by a dry run (`VALIDATION_MODE`) before every load.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Landing area | A named internal stage, `RAW.OLIST_STAGE`, with the file format attached and a directory table | Created by SQL in the repo, owned by the pipeline role. The directory table lets Snowsight list the files. |
| Upload | A Python script using `PUT` (`02_upload_files.py`) | `PUT` cannot run in a Snowsight worksheet. A script is repeatable and builds the path from the repo folder. `OVERWRITE=FALSE`: running it twice duplicates nothing. |
| Reading rules | One file format, `RAW.OLIST_CSV` (see below) | All files follow the same conventions. Each setting comes from profiling the files. |
| Column types | Every source column is `VARCHAR` | RAW is as received: no row can be rejected for a type reason, no information is lost (zip prefixes keep leading zeros). Typing belongs in dbt staging, where it is tested. |
| Provenance | `_source_file` (`METADATA$FILENAME`), `_source_row` (`METADATA$FILE_ROW_NUMBER`), `_loaded_at` (`METADATA$START_SCAN_TIME`) | Any value can be traced to a file and a record. Snowflake recommends `START_SCAN_TIME` over a `CURRENT_TIMESTAMP()` default for load time. |
| Constraints | None | Snowflake does not enforce keys. RAW accepts duplicates and blanks as they arrive; staging tests them. |
| Keep the staged files | Yes (no `PURGE`) | They are the evidence of exactly what was loaded, and the rebuild path reloads from them. |
| **Bad rows** | **`ON_ERROR = ABORT_STATEMENT`** | See below. |
| Geolocation | Not loaded | The analysis works at state level, which `customers` and `sellers` already carry. |

### File format settings

| Setting | Value | Evidence |
|---|---|---|
| `FIELD_OPTIONALLY_ENCLOSED_BY` | `"` (the default is NONE) | Review comments contain commas and line breaks inside quotes. Quoting is inconsistent, hence "optionally". |
| `SKIP_HEADER` | 1 | Every file has one header line. |
| `ENCODING`, `SKIP_BYTE_ORDER_MARK` | `UTF8`, `TRUE` | Every file is valid UTF-8. The category file starts with a byte-order mark. |
| `RECORD_DELIMITER` | left at its default (a new line) | The reviews and category files use Windows `\r\n`. Verified: 0 stray `\r` in any loaded table. |
| `EMPTY_FIELD_AS_NULL` | `TRUE` | Blank fields are common, for example orders not yet delivered. |
| `ERROR_ON_COLUMN_COUNT_MISMATCH` | `TRUE` | Applies to a plain `COPY` and the dry run, **not** to the SELECT-form load (see "How bad rows are handled"). |
| `TRIM_SPACE`, `REPLACE_INVALID_CHARACTERS` | `FALSE` | RAW does no cleaning. Invalid UTF-8 would fail loudly instead of being replaced silently. |

### How bad rows are handled

**`ON_ERROR = ABORT_STATEMENT`.** The rule is that no bad row is silently dropped.

1. Every source column is text, so type errors cannot happen. A row that fails would mean my reading rules are wrong, which must be fixed, not skipped.
2. It is all-or-nothing per table. One `COPY` loads one file into one table, so a failure leaves the table untouched and a re-run is clean.
3. `CONTINUE` would let counts drift silently, and `SKIP_FILE` would drop a whole file silently.

**The load cannot check the number of fields per row, so a dry run does.** To record the file name and row number, the load has to use the SELECT form of `COPY INTO`, and in that form Snowflake ignores `ERROR_ON_COLUMN_COUNT_MISMATCH`. I confirmed this on the real orders file: asking for a 9th field in an 8-field file raises no error and returns NULL. `04_dry_run.py` therefore runs every file through `VALIDATION_MODE = RETURN_ERRORS` into a temporary table that mirrors the CSV header, which does check the field count. I also confirmed it catches the problem: into a 9-column table, it reports "Number of columns in file (8) does not match that of the corresponding table (9)".

**`VALIDATE()` is not used.** It does not work with a transforming copy, and it returns nothing for `ABORT_STATEMENT` loads.

## What I found

### Dry run (`04_dry_run.py`)

0 error rows in all eight files.

### Load (`04_load.sql`), as reported by `COPY`

| Table | Status | Rows parsed | Rows loaded | Errors |
|---|---|---:|---:|---:|
| `ORDERS` | LOADED | 99,441 | 99,441 | 0 |
| `ORDER_ITEMS` | LOADED | 112,650 | 112,650 | 0 |
| `CUSTOMERS` | LOADED | 99,441 | 99,441 | 0 |
| `ORDER_PAYMENTS` | LOADED | 103,886 | 103,886 | 0 |
| `ORDER_REVIEWS` | LOADED | 99,224 | 99,224 | 0 |
| `PRODUCTS` | LOADED | 32,951 | 32,951 | 0 |
| `SELLERS` | LOADED | 3,095 | 3,095 | 0 |
| `PRODUCT_CATEGORY_NAME_TRANSLATION` | LOADED | 71 | 71 | 0 |

### Reconciliation (`05_reconcile.py`): four independent counts per table

| Table | CSV file | Staged | `COPY` loaded | In table | Result |
|---|---:|---:|---:|---:|---|
| `ORDERS` | 99,441 | 99,441 | 99,441 | 99,441 | OK |
| `ORDER_ITEMS` | 112,650 | 112,650 | 112,650 | 112,650 | OK |
| `CUSTOMERS` | 99,441 | 99,441 | 99,441 | 99,441 | OK |
| `ORDER_PAYMENTS` | 103,886 | 103,886 | 103,886 | 103,886 | OK |
| `ORDER_REVIEWS` | 99,224 | 99,224 | 99,224 | 99,224 | OK |
| `PRODUCTS` | 32,951 | 32,951 | 32,951 | 32,951 | OK |
| `SELLERS` | 3,095 | 3,095 | 3,095 | 3,095 | OK |
| `PRODUCT_CATEGORY_NAME_TRANSLATION` | 71 | 71 | 71 | 71 | OK |

The CSV count comes from Python's `csv` module, independent of Snowflake. The reviews file has 104,720 physical lines but 99,224 records, because 3,852 comments contain line breaks inside quotes. `_source_row` for reviews runs 1 to 99,224: it counts records, not lines.

### Checks on the loaded data (`05_check_loaded_data.sql`)

| Assumption | Result |
|---|---|
| Windows line endings leave no stray `\r` | 0 stray carriage returns in the last field of every table |
| Blank fields load as NULL, not empty text | Every blank is NULL. No column holds an empty string. |
| Zip prefixes keep leading zeros | All 5 characters long. 23,995 customer and 1,027 seller prefixes start with `0`. |
| Portuguese accents read correctly | 22,658 review messages, 2,636 review titles and 3 seller cities contain accents; **0** show the garbling of a wrong encoding. Customer city names are ASCII-only, as profiled. |
| Facts from the pre-load profile hold in the loaded tables | 14 of 14 reproduced exactly: statuses, delivered count, blank dates, key uniqueness, repeating `review_id`s (789) and orders with several reviews (547), people with several orders (2,997), `not_defined` payments (3), products with no category (610) |

### Blanks, in numbers (NULLs in RAW)

| Table | Column | NULLs |
|---|---|---:|
| `ORDERS` | `order_approved_at` | 160 |
| `ORDERS` | `order_delivered_carrier_date` | 1,783 |
| `ORDERS` | `order_delivered_customer_date` | 2,965 |
| `ORDER_REVIEWS` | `review_comment_title` | 87,656 |
| `ORDER_REVIEWS` | `review_comment_message` | 58,247 |
| `PRODUCTS` | category, name length, description length, photos | 610 each |
| `PRODUCTS` | weight, length, height, width | 2 each |

### Rebuild path (tested)

`truncate_raw_tables.sql` empties the tables, which also clears Snowflake's record of which files were loaded ("no history"). Re-running `04_load.sql` then loads every file again with the same counts, and `05_reconcile.py` is green again. Running `04_load.sql` a **second time without truncating** loads nothing (`Copy executed with 0 files processed`), so it cannot duplicate rows.

## Assumptions

- **Types:** none applied in RAW. Timestamps are text in the form `YYYY-MM-DD HH24:MI:SS` with no time zone; money and counts are text. Typing is a staging decision.
- **Time zones:** the source timestamps carry no time zone. I assume they are Brazil local time, which I have not verified. `_loaded_at` is a real timestamp and shows in the Snowflake account's default zone (America/Los_Angeles).
- **Encoding:** UTF-8 throughout, verified on the loaded data (accents intact, byte-order mark skipped).
- **Malformed rows:** none found. The dry run reported 0 error rows, and `COPY` reported 0 errors.
- **Blanks:** a blank field is NULL. No empty strings are present in RAW. I could not tell from the loaded data whether the source used any explicitly empty quoted `""` values, because none arrived as empty text.
- **Keys:** not enforced in RAW. Known duplicates (for example repeated `review_id`s) are kept and handled in staging.
- **Customers:** `customer_id` is new on every order, so a person is identified by `customer_unique_id`.

## Limits of this approach, and what I would do in production

- This is a full reload of static files. For recurring feeds I would load incrementally (new files only, keyed on load metadata) with Snowpipe or a scheduled task.
- `COPY_HISTORY` keeps 14 days. I would persist each load's counts to a log table for a lasting audit trail.
- I would alert on any non-zero `ERRORS_SEEN` or on a row count that moves unexpectedly between loads.
- I would watch for schema drift (a changed header) before loading, for example by comparing the header with the table.
- The private key is unencrypted on disk, which is acceptable for a trial account; in production it would be in a secrets manager.

## Manual steps and versions

See [README.md](README.md): the one-off manual steps (key pair, account setup in Snowsight, `.env`, downloading the data) and the pinned versions.
