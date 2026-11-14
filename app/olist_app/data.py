"""Where the app's numbers come from.

Live: when the pipeline's Snowflake settings are in the environment (the same variables as the ingest scripts and dbt), the
app reads the marts directly. Snapshot: otherwise, or if Snowflake cannot be reached, it reads app/snapshot/snapshot.json,
a small file of aggregate results written by app/make_snapshot.py. The snapshot holds no order-level rows. Both paths run
the same queries, so the app looks the same either way, and the page says which one it is using.
"""
from __future__ import annotations

import json
import os
from datetime import date
from decimal import Decimal
from pathlib import Path

import pandas as pd
import streamlit as st

from olist_app import queries

SNAPSHOT_PATH = Path(__file__).resolve().parent.parent / "snapshot" / "snapshot.json"
REQUIRED_VARIABLES = (
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PRIVATE_KEY_PATH",
    "SNOWFLAKE_ROLE",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
)


def live_configured() -> bool:
    """True when every Snowflake setting is present and the snapshot has not been forced with OLIST_APP_SOURCE=snapshot."""
    if os.environ.get("OLIST_APP_SOURCE", "").strip().lower() == "snapshot":
        return False
    return all(os.environ.get(name) for name in REQUIRED_VARIABLES)


def _plain(value):
    """Decimal to float and date to text, so results are JSON-safe and plot cleanly."""
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, date):
        return value.isoformat()
    return value


def fetch_live() -> dict:
    """Run every query against Snowflake and return plain Python data (also what make_snapshot.py saves)."""
    import snowflake.connector

    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.environ["SNOWFLAKE_ROLE"],
        warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
        database=os.environ["SNOWFLAKE_DATABASE"],
    )
    try:

        def run(sql: str) -> list[dict]:
            cur = conn.cursor()
            try:
                cur.execute(sql)
                names = [c[0].lower() for c in cur.description]
                return [{n: _plain(v) for n, v in zip(names, row)} for row in cur.fetchall()]
            finally:
                cur.close()

        tables = {name: run(sql) for name, sql in queries.TABLES.items()}
        campaign = run(queries.CAMPAIGN_INPUTS)[0]
        freights = [row["freight_total"] for row in run(queries.LATER_ORDER_FREIGHTS)]
    finally:
        conn.close()
    return {"tables": tables, "campaign": campaign, "freights": freights}


def read_snapshot() -> dict:
    return json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))


def _bundle(payload: dict, source: str, as_of: str, note: str = "") -> dict:
    return {
        "tables": {name: pd.DataFrame(rows) for name, rows in payload["tables"].items()},
        "campaign": payload["campaign"],
        "freights": payload["freights"],
        "source": source,
        "as_of": as_of,
        "note": note,
    }


@st.cache_data(ttl=3600, show_spinner="Reading the marts")
def load() -> dict:
    """Every table the pages need, from Snowflake if it is configured and reachable, else from the snapshot."""
    snapshot = read_snapshot()
    if live_configured():
        try:
            return _bundle(fetch_live(), "live", date.today().isoformat())
        except Exception as error:  # a wrong key, a suspended account, no network: say so and fall back
            note = f"Snowflake could not be reached ({type(error).__name__}), so this shows the saved snapshot."
            return _bundle(snapshot, "snapshot", snapshot["generated_on"], note)
    return _bundle(snapshot, "snapshot", snapshot["generated_on"])


def source_note(bundle: dict) -> str:
    if bundle["source"] == "live":
        return f"Read from Snowflake on {bundle['as_of']}."
    base = f"Saved snapshot of the marts from {bundle['as_of']}. Set the Snowflake variables to read them live."
    return f"{bundle['note']} {base}".strip()
