import sqlite3
import pandas as pd
from collections import Counter

DB_FILE = "database/retail.db"
TABLE = "online_retail_clean"

conn = sqlite3.connect(DB_FILE)
df = pd.read_sql(f"SELECT InvoiceNo, Description FROM {TABLE}", conn)
conn.close()

def get_recommendations(product_query, top_n=5):
    # find matching products
    matches = df["Description"].dropna().unique()
    matches = [m for m in matches if product_query.upper() in m.upper()]

    if not matches:
        print(f"No products found matching '{product_query}'")
        return

    # use closest match
    product = matches[0]
    print(f"\nFinding co-purchases for: {product}")

    # get all invoices containing this product
    target_invoices = df[df["Description"] == product]["InvoiceNo"].unique()

    if len(target_invoices) == 0:
        print("No invoices found for this product.")
        return

    # get all OTHER items on those invoices
    co_purchases = df[
        (df["InvoiceNo"].isin(target_invoices)) &
        (df["Description"] != product)
    ]["Description"]

    counts = Counter(co_purchases)
    total_invoices = len(target_invoices)

    print(f"Appeared in {total_invoices} invoices\n")
    print(f"{'Rank':<5} {'Product':<50} {'Count':>6} {'% of baskets':>13}")
    print("-" * 78)
    # % of baskets = "of all the times someone bought X, what fraction of those trips also included Y?"

    for i, (item, count) in enumerate(counts.most_common(top_n), 1):
        pct = count / total_invoices * 100
        print(f"{i:<5} {item:<50} {count:>6} {pct:>12.1f}%")

# ── RUN ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    while True:
        query = input("\nEnter a product name (or 'quit' to exit): ").strip()
        if query.lower() == "quit":
            break
        get_recommendations(query, top_n=10)