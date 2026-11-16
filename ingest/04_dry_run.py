"""Dry run: check every staged file BEFORE loading it (ingest step 2.4)."""
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


def csv_header(filename):
    with open(DATA_DIR / filename, encoding="utf-8-sig", newline="") as f:  # utf-8-sig drops the BOM
        return next(csv.reader(f))


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
    failed = 0
    try:
        cur = conn.cursor()
        print(f"{'staged file':<46}{'error rows':>11}  result")
        for table, filename in TABLES.items():
            scratch = f"ELIO_OLIST.RAW.{table}_DRYRUN"
            columns = ", ".join(f"{name} VARCHAR" for name in csv_header(filename))
            cur.execute(f"CREATE OR REPLACE TEMPORARY TABLE {scratch} ({columns})")
            cur.execute(
                f"COPY INTO {scratch} FROM {STAGE}/{filename}.gz "
                f"FILE_FORMAT = (FORMAT_NAME = '{FILE_FORMAT}') VALIDATION_MODE = RETURN_ERRORS"
            )
            errors = cur.fetchall()
            print(f"{filename + '.gz':<46}{len(errors):>11}  {'OK' if not errors else 'WOULD FAIL'}")
            if errors:
                failed += 1
                for row in errors[:3]:
                    print("    first problem:", str(row[0])[:160])
    finally:
        conn.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
