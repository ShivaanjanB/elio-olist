"""Reconcile row counts after the load (ingest step 2.5)."""
import csv
import os
import sys
import warnings
from pathlib import Path

import snowflake.connector

warnings.filterwarnings("ignore", category=FutureWarning)  # harmless connector notice

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
STAGE = "@ELIO_OLIST.RAW.OLIST_STAGE"
FILE_FORMAT = "ELIO_OLIST.RAW.OLIST_CSV"
TABLES = {
    "ORDERS": "olist_orders_dataset.csv",
    "ORDER_ITEMS": "olist_order_items_dataset.csv",
    "CUSTOMERS": "olist_customers_dataset.csv",
    "ORDER_PAYMENTS": "olist_order_payments_dataset.csv",
    "ORDER_REVIEWS": "olist_order_reviews_dataset.csv",
    "PRODUCTS": "olist_products_dataset.csv",
    "SELLERS": "olist_sellers_dataset.csv",
    "PRODUCT_CATEGORY_NAME_TRANSLATION": "product_category_name_translation.csv",
}
REQUIRED = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY_PATH",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
]


def csv_records(filename):
    """Records in the CSV, header excluded. The csv module follows quotes, so multi-line fields count once."""
    with open(DATA_DIR / filename, encoding="utf-8-sig", newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def main():
    missing = [n for n in REQUIRED if not os.environ.get(n)]
    if missing:
        sys.exit(
            "Missing settings: " + ", ".join(missing) + "\n"
            "Load them first, from the repo root:  . .\\scripts\\load_env.ps1"
        )
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
    )
    problems = 0
    try:
        cur = conn.cursor()
        print(f"{'table':<36}{'csv file':>10}{'staged':>10}{'COPY loaded':>13}{'in table':>10}  {'COPY status':<12}{'errors':>7}  result")
        for table, filename in TABLES.items():
            in_csv = csv_records(filename)

            cur.execute(f"SELECT COUNT(*) FROM {STAGE}/{filename}.gz (FILE_FORMAT => '{FILE_FORMAT}')")
            staged = cur.fetchone()[0]

            # COPY_HISTORY keeps 14 days, so look back the full 14 (a shorter window reports "no history" a few days after the load)
            cur.execute(
                "SELECT row_count, error_count, status "
                f"FROM TABLE(ELIO_OLIST.INFORMATION_SCHEMA.COPY_HISTORY("
                f"TABLE_NAME => 'ELIO_OLIST.RAW.{table}', START_TIME => DATEADD(days, -14, CURRENT_TIMESTAMP()))) "
                "ORDER BY last_load_time DESC LIMIT 1"
            )
            history = cur.fetchone()
            copy_loaded, copy_errors, copy_status = history if history else (None, None, "no history")

            cur.execute(f"SELECT COUNT(*) FROM ELIO_OLIST.RAW.{table}")
            in_table = cur.fetchone()[0]

            ok = in_csv == staged == copy_loaded == in_table and copy_errors == 0
            problems += 0 if ok else 1
            print(
                f"{table:<36}{in_csv:>10,}{staged:>10,}{(copy_loaded if copy_loaded is not None else -1):>13,}"
                f"{in_table:>10,}  {str(copy_status):<12}{(copy_errors if copy_errors is not None else -1):>7}  "
                f"{'OK' if ok else 'MISMATCH'}"
            )
    finally:
        conn.close()
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
