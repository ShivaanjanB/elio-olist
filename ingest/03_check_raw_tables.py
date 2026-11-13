"""Check that each RAW table matches its CSV header (ingest step 2.3). Read-only.

COPY INTO maps CSV fields to table columns BY POSITION, so a table must have the CSV's columns
in the CSV's order. For every table this compares Snowflake's column list with the header line
of the matching file in data/raw/, and checks:
  * source columns: same names, same order, all text (VARCHAR)
  * then the three label columns: _source_file (text), _source_row (number), _loaded_at (timestamp)
Row counts are printed for information only (0 before the load).

Run from the repo root, after `. .\\scripts\\load_env.ps1`:
    .\\.venv\\Scripts\\python.exe ingest\\03_check_raw_tables.py
Exits with an error if anything does not match.
"""
import csv
import os
import sys
import warnings
from pathlib import Path

import snowflake.connector

warnings.filterwarnings("ignore", category=FutureWarning)  # harmless connector notice

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
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
LABELS = [("_SOURCE_FILE", "TEXT"), ("_SOURCE_ROW", "NUMBER"), ("_LOADED_AT", "TIMESTAMP_LTZ")]
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
    problems = 0
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT table_name, column_name, data_type "
            "FROM ELIO_OLIST.INFORMATION_SCHEMA.COLUMNS "
            "WHERE table_schema = 'RAW' ORDER BY table_name, ordinal_position"
        )
        actual = {}
        for table, column, data_type in cur.fetchall():
            actual.setdefault(table, []).append((column, data_type))

        print(f"{'table':<36}{'source cols':>12}  {'result':<10}{'rows':>8}")
        for table, filename in TABLES.items():
            header = [h.upper() for h in csv_header(filename)]
            expected = [(h, "TEXT") for h in header] + LABELS
            found = actual.get(table, [])
            ok = found == expected
            cur.execute(f"SELECT COUNT(*) FROM ELIO_OLIST.RAW.{table}") if found else None
            rows = cur.fetchone()[0] if found else "-"
            print(f"{table:<36}{len(header):>12}  {'OK' if ok else 'MISMATCH':<10}{rows:>8}")
            if not ok:
                problems += 1
                print("   expected:", expected)
                print("   found:   ", found)
    finally:
        conn.close()
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
