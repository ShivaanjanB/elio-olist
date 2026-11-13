"""Pre-load profile of the Olist CSVs: encoding, BOM, line endings, record counts,
embedded newlines, ragged rows, and candidate-key uniqueness. Stdlib only."""
import csv
import sys
from collections import Counter
from pathlib import Path

KEYS = {
    "olist_orders_dataset.csv": [["order_id"], ["customer_id"]],
    "olist_customers_dataset.csv": [["customer_id"], ["customer_unique_id"]],
    "olist_order_items_dataset.csv": [["order_id", "order_item_id"]],
    "olist_order_payments_dataset.csv": [["order_id", "payment_sequential"]],
    "olist_order_reviews_dataset.csv": [["review_id"], ["order_id"], ["review_id", "order_id"]],
    "olist_products_dataset.csv": [["product_id"]],
    "olist_sellers_dataset.csv": [["seller_id"]],
    "olist_geolocation_dataset.csv": [["geolocation_zip_code_prefix"]],
    "product_category_name_translation.csv": [["product_category_name"]],
}

folder = Path(sys.argv[1])
csv.field_size_limit(10_000_000)
for path in sorted(folder.glob("*.csv")):
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    try:
        raw.decode("utf-8")
        utf8 = "ok"
    except UnicodeDecodeError as e:
        utf8 = f"FAIL at byte {e.start}"
    crlf = raw.count(b"\r\n")
    physical_lines = raw.count(b"\n")
    non_ascii_bytes = sum(1 for b in raw if b > 127)

    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    width = Counter(len(r) for r in rows)
    multiline = sum(1 for r in rows if any("\n" in c or "\r" in c for c in r))
    empty_cells = Counter()
    for r in rows:
        for name, val in zip(header, r):
            if val == "":
                empty_cells[name] += 1

    print(f"\n=== {path.name}  ({len(raw)/1e6:.1f} MB)")
    print(f"  utf8={utf8}  bom={bom}  crlf_lines={crlf}  physical_lines={physical_lines}  non_ascii_bytes={non_ascii_bytes}")
    print(f"  records={len(rows)}  header_cols={len(header)}  row_widths={dict(width)}  rows_with_embedded_newline={multiline}")
    print(f"  header={header}")
    if empty_cells:
        print(f"  empty_cells={dict(empty_cells)}")
    idx = {h: i for i, h in enumerate(header)}
    for key in KEYS.get(path.name, []):
        vals = Counter(tuple(r[idx[k]] for k in key) for r in rows if len(r) == len(header))
        dupes = sum(1 for v in vals.values() if v > 1)
        print(f"  key {key}: distinct={len(vals)}  values_with_dupes={dupes}")
