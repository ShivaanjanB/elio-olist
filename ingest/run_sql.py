"""Run a .sql file (or one inline statement) in Snowflake as the pipeline service user."""
import os
import sys
import warnings

import snowflake.connector

warnings.filterwarnings("ignore", category=FutureWarning)  # harmless connector notice

REQUIRED = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY_PATH",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
]
MAX_ROWS = 60  # rows printed per statement


def read_sql(args):
    if len(args) == 2 and args[0] == "--sql":
        return args[1]
    if len(args) == 1:
        with open(args[0], encoding="utf-8") as f:
            return f.read()
    sys.exit("Usage: run_sql.py <file.sql>   or   run_sql.py --sql \"<statement>\"")


def main():
    missing = [n for n in REQUIRED if not os.environ.get(n)]
    if missing:
        sys.exit(
            "Missing settings: " + ", ".join(missing) + "\n"
            "Load them first, from the repo root:  . .\\scripts\\load_env.ps1"
        )
    sql_text = read_sql(sys.argv[1:])

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
    )
    try:
        # execute_string splits the text into statements and runs them in order
        for n, cur in enumerate(conn.execute_string(sql_text, remove_comments=True), start=1):
            first_line = " ".join(cur.query.split())[:90]
            print(f"[{n}] {first_line}")
            for row in cur.fetchmany(MAX_ROWS):
                print("     ", row)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
