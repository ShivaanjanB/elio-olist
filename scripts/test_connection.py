"""Connection test: sign in as the pipeline service user with its key pair and report who we are."""
import os
import sys

import snowflake.connector

REQUIRED = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY_PATH",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
]

missing = [name for name in REQUIRED if not os.environ.get(name)]
if missing:
    sys.exit(
        "Missing settings: " + ", ".join(missing) + "\n"
        "Load them first, from the repo root:  . .\\scripts\\load_env.ps1"
    )

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],  # key pair, no password
    role=os.environ["SNOWFLAKE_ROLE"],
    warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    database=os.environ["SNOWFLAKE_DATABASE"],
)

try:
    cur = conn.cursor()

    # 1. Who am I, in which role, using which worker, in which cabinet?
    cur.execute(
        "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), "
        "CURRENT_DATABASE(), CURRENT_VERSION()"
    )
    user, role, warehouse, database, version = cur.fetchone()
    print("Signed in OK")
    print(f"  user      : {user}")
    print(f"  role      : {role}")
    print(f"  warehouse : {warehouse}")
    print(f"  database  : {database}")
    print(f"  snowflake : {version}")

    # 2. Can this role see the RAW drawer?
    cur.execute(f"SHOW SCHEMAS IN DATABASE {database}")
    schemas = [row[1] for row in cur.fetchall()]
    print(f"  schemas   : {', '.join(schemas)}")
    print("RAW drawer visible:", "RAW" in schemas)
finally:
    conn.close()
