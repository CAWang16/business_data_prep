import sqlite3
import pandas as pd

conn = sqlite3.connect("database/clean_retail.db")

tables = [
    "clean_product_sales",
    "manual_product_sales",
    "cancellations",
    "admin_invoices",
    "inventory_adjustments",
    "free_items",
    "gift_vouchers",
    "dcgs_rows",
    "shipping_fees",
    "other_special_rows",
]

print("\nTable row counts")
print("-----------------")

for table in tables:
    count = pd.read_sql(f"SELECT COUNT(*) as count FROM {table}", conn)
    print(f"{table}: {count['count'][0]:,}")


overlap = pd.read_sql("""
SELECT COUNT(*) as overlap_count
FROM clean_product_sales cps
JOIN manual_product_sales mps
ON cps.invoice_no = mps.invoice_no
AND cps.stock_code = mps.stock_code
""", conn)

print(f"\nOverlap between clean and manual: {overlap['overlap_count'][0]}")


conn.close()