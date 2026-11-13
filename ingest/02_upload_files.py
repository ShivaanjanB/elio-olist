"""Upload the Olist CSVs to the internal stage with PUT (ingest step 2.2).

PUT cannot run from a Snowsight worksheet, so it runs here, through the Python connector,
signed in as the pipeline service user with its key pair. Prints no secrets.

What it does for each file listed below:
  * PUT the file from data/raw/ to @ELIO_OLIST.RAW.OLIST_STAGE
  * AUTO_COMPRESS=TRUE: Snowflake gzips it, so the staged name ends in .csv.gz
  * OVERWRITE=FALSE (the default, written out): running this twice never duplicates or
    replaces a staged file. Status SKIPPED on a second run means "already there".
Then it LISTs the stage.

Geolocation (olist_geolocation_dataset.csv) is deliberately NOT uploaded: the analysis works
at state level, which customers and sellers already carry (see ingest/README.md).

Run from the repo root, after `. .\\scripts\\load_env.ps1`:
    .\\.venv\\Scripts\\python.exe ingest\\02_upload_files.py
"""
import os
import sys
import warnings
from pathlib import Path

import snowflake.connector

warnings.filterwarnings("ignore", category=FutureWarning)  # harmless connector notice

STAGE = "@ELIO_OLIST.RAW.OLIST_STAGE"
DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
FILES = [
    "olist_orders_dataset.csv",
    "olist_order_items_dataset.csv",
    "olist_customers_dataset.csv",
    "olist_order_payments_dataset.csv",
    "olist_order_reviews_dataset.csv",
    "olist_products_dataset.csv",
    "olist_sellers_dataset.csv",
    "product_category_name_translation.csv",
]
REQUIRED = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY_PATH",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
]


def main():
    missing = [n for n in REQUIRED if not os.environ.get(n)]
    if missing:
        sys.exit(
            "Missing settings: " + ", ".join(missing) + "\n"
            "Load them first, from the repo root:  . .\\scripts\\load_env.ps1"
        )
    absent = [f for f in FILES if not (DATA_DIR / f).is_file()]
    if absent:
        sys.exit("Not found in data/raw/: " + ", ".join(absent))

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
    )
    try:
        cur = conn.cursor()
        print(f"{'file':<42}{'status':<10}{'bytes in':>12}{'bytes staged':>14}")
        for name in FILES:
            path = (DATA_DIR / name).as_posix()  # forward slashes, as PUT expects on Windows
            cur.execute(f"PUT 'file://{path}' {STAGE} AUTO_COMPRESS=TRUE OVERWRITE=FALSE")
            source, target, src_size, tgt_size, _, _, status, _ = cur.fetchone()
            print(f"{name:<42}{status:<10}{src_size:>12,}{tgt_size:>14,}")

        print(f"\nLIST {STAGE}")
        cur.execute(f"LIST {STAGE}")
        for stage_name, size, _md5, modified in cur.fetchall():
            print(f"  {stage_name.split('/', 1)[-1]:<46}{size:>12,}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
