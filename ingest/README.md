# Ingest: Olist CSVs into Snowflake `RAW`

## One-off manual steps

### 1. Generate a key pair for the service user
The pipeline signs in as `ELIO_SVC`, a Snowflake service user that has no password and authenticates only with an RSA key. The private key stays outside the repo.

From the repo root, in PowerShell (needs `openssl`, which ships with Git for Windows):

```powershell
.\scripts\new_keypair.ps1
```

The script writes `rsa_key.p8` (private) and `rsa_key.pub` (public) to `~\.snowflake\elio\`, restricts the private key to your Windows account, then prints the public key on one line (to paste into `00_setup_account.sql`) and its SHA-256 fingerprint (to compare with Snowflake's `RSA_PUBLIC_KEY_FP`). It refuses to overwrite an existing key unless you pass `-Force`.

The private key is unencrypted on disk, which is acceptable for a trial account; in production I would encrypt it or keep it in a secrets manager.

### 2. Run the account setup
1. Open a Snowsight worksheet and switch the role to `ACCOUNTADMIN`.
2. Paste in [`00_setup_account.sql`](00_setup_account.sql).
3. Replace `<PASTE_ONE_LINE_PUBLIC_KEY_HERE>` with the one-line key.
4. Run all statements.

The final `DESC USER ELIO_SVC` should show `RSA_PUBLIC_KEY_FP = SHA256:…`.

### 3. Point local tools at the account
Copy `.env.example` to `.env` and fill it in. Then load it into your shell:
- Windows: `. .\scripts\load_env.ps1`
- macOS/Linux: `set -a; . ./.env; set +a`

## Pre-load profile of the files
Before loading anything, I profiled the raw CSVs with `python ingest/profile_csvs.py data/raw` (stdlib only):

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

Across all files:
- **Encoding:** every file is valid UTF-8. Accented Portuguese text appears in reviews, geolocation, sellers and the category translation; customer city names are ASCII-only.
- **Zip prefixes:** always 5 characters with leading zeros (e.g. `01151`), so they must stay text.
- **Quoting:** inconsistent; some IDs are quoted and some aren't, even within one row.
- **Timestamps:** `YYYY-MM-DD HH24:MI:SS`, no time zone.

**Why geolocation is skipped:** the analysis works at state level, which `customers` and `sellers` already carry. Geolocation would only add map coordinates, and using it would first mean collapsing a million rows to one per zip prefix.
