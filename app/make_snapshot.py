"""Write app/snapshot/snapshot.json from Snowflake: the aggregate results the app draws, so it can run without credentials.

From the repo root, after loading the settings (see README):
    . .\\scripts\\load_env.ps1
    cd app
    ..\\.venv\\Scripts\\python.exe make_snapshot.py

The file holds a few hundred numbers (one row per state, band or quarter) and the freight of 3,264 later orders. It holds no
customer or order identifiers.
"""
import json
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from olist_app import data  # noqa: E402


def main() -> None:
    if not data.live_configured():
        sys.exit("Set the Snowflake variables first: . .\\scripts\\load_env.ps1 (see README).")
    payload = data.fetch_live()
    payload["generated_on"] = date.today().isoformat()
    payload["source"] = "ELIO_OLIST.MARTS"
    data.SNAPSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)
    data.SNAPSHOT_PATH.write_text(json.dumps(payload, indent=1, sort_keys=True), encoding="utf-8")
    rows = {name: len(rows) for name, rows in payload["tables"].items()}
    print(f"Wrote {data.SNAPSHOT_PATH} ({data.SNAPSHOT_PATH.stat().st_size / 1024:.0f} KB)")
    print("rows per table:", rows, "| freights:", len(payload["freights"]))


if __name__ == "__main__":
    main()
