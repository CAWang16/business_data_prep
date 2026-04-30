import sqlite3
import pandas as pd

DB_FILE = "database/retail.db"
RAW_TABLE = "online_retail"

conn = sqlite3.connect(DB_FILE)
df = pd.read_sql(f"SELECT * FROM {RAW_TABLE}", conn)
conn.close()

# Standardize column names
df = df.rename(columns={
    "Customer ID": "CustomerID",
    "Invoice": "InvoiceNo"
})

# ============================================================
# SPLIT DECISION EDA — OVERVIEW
# ============================================================

print("\n" + "=" * 60)
print("SPLIT DECISION EDA — OVERVIEW")
print("=" * 60)

print(f"Total rows: {len(df):,}")
print(f"Columns: {df.shape[1]}")

print("\nColumn names:")
print(df.columns.tolist())

# ============================================================
# INITIAL SPLIT CANDIDATE COUNTS
# ============================================================

# Key logical masks (no filtering yet)
is_return = df["Quantity"] < 0
is_free = df["Price"] == 0
is_admin = df["InvoiceNo"].astype(str).str.startswith("A")

print("\n" + "=" * 60)
print("INITIAL SPLIT CANDIDATE COUNTS")
print("=" * 60)

print(f"Returns (Quantity < 0): {is_return.sum():,} ({is_return.mean():.2%})")
print(f"Free items (Price = 0): {is_free.sum():,} ({is_free.mean():.2%})")
print(f"Admin (InvoiceNo starts with 'A'): {is_admin.sum():,} ({is_admin.mean():.2%})")

print("\nOverlap checks:")
print(f"Return + Free: {(is_return & is_free).sum():,}")
print(f"Return + Admin: {(is_return & is_admin).sum():,}")
print(f"Free + Admin: {(is_free & is_admin).sum():,}")

# ============================================================
# INVOICE TYPE ANALYSIS
# ============================================================

invoice_prefix = df["InvoiceNo"].astype(str).str[0]

print("\n" + "=" * 60)
print("RETURNS BY INVOICE TYPE")
print("=" * 60)
print(pd.crosstab(invoice_prefix, is_return))

print("\n" + "=" * 60)
print("FREE ITEMS BY INVOICE TYPE")
print("=" * 60)
print(pd.crosstab(invoice_prefix, is_free))

# ============================================================
# STOCKCODE TYPE ANALYSIS
# ============================================================

df["StockCode"] = df["StockCode"].astype(str).str.strip()

# Treat as normal StockCodes: 5 digits, 5 digits+1 letter, or 5 digits+2 letters
is_special_stock = ~df["StockCode"].astype(str).str.match(r"^\d{5}([A-Za-z]{1,2})?$")

print("\n" + "=" * 60)
print("SPECIAL STOCKCODE COUNT (UPDATED DEFINITION)")
print("=" * 60)

special_stockcodes = df.loc[is_special_stock, "StockCode"]

print(f"Total special StockCode rows: {len(special_stockcodes):,}")
print(f"Unique special StockCodes: {special_stockcodes.nunique():,}")

print("\nExamples:")
print(special_stockcodes.unique()[:62])

print("\n" + "=" * 60)
print("RETURNS VS STOCKCODE TYPE")
print("=" * 60)
print(pd.crosstab(is_special_stock, is_return))

print("\n" + "=" * 60)
print("FREE ITEMS VS STOCKCODE TYPE")
print("=" * 60)
print(pd.crosstab(is_special_stock, is_free))

print("\n" + "=" * 60)
print("SPECIAL STOCKCODE DISTRIBUTION BY INVOICE TYPE")
print("=" * 60)
print(pd.crosstab(invoice_prefix, is_special_stock))

# ============================================================
# CRITICAL CHECK: INVOICE vs QUANTITY MISMATCH
# ============================================================

is_c_invoice = df["InvoiceNo"].astype(str).str.startswith("C")
is_negative_qty = df["Quantity"] < 0

print("\n" + "=" * 60)
print("INVOICE / QUANTITY MISMATCH CHECK")
print("=" * 60)

print(f"Negative quantity but NOT C invoice: {(is_negative_qty & ~is_c_invoice).sum():,}")
print(f"C invoice but NOT negative quantity: {(is_c_invoice & ~is_negative_qty).sum():,}")

cols_to_show = [
    "InvoiceNo", "StockCode", "Description",
    "Quantity", "Price", "CustomerID", "Country"
]

print("\nExamples: negative quantity but NOT C invoice")
print(df.loc[is_negative_qty & ~is_c_invoice, cols_to_show].head(20).to_string(index=False))

print("\nExamples: C invoice but NOT negative quantity")
print(df.loc[is_c_invoice & ~is_negative_qty, cols_to_show].head(20).to_string(index=False))

# ============================================================
# PROPOSED GROUPS (NOT FINAL — FOR EXPLORATION)
# ============================================================

# remove admin rows
df_no_admin = df[~is_admin]

# keep naming neutral until logic is finalized
c_invoice_rows = df_no_admin[df_no_admin["InvoiceNo"].str.startswith("C")]

non_returns = df_no_admin[~df_no_admin["InvoiceNo"].str.startswith("C")]

clean_sales = non_returns[
    (non_returns["Quantity"] > 0) &
    (non_returns["Price"] > 0)
]

free_items = non_returns[
    (non_returns["Quantity"] > 0) &
    (non_returns["Price"] == 0)
]

# ============================================================
# INSPECT TOP STOCKCODES BY GROUP
# ============================================================

print("\n" + "=" * 60)
print("TOP STOCKCODES BY PROPOSED GROUP")
print("=" * 60)

print("\nClean sales:")
print(clean_sales["StockCode"].value_counts().head(10).to_string())

print("\nC-invoice rows (candidate returns):")
print(c_invoice_rows["StockCode"].value_counts().head(10).to_string())

print("\nFree items:")
print(free_items["StockCode"].value_counts().head(10).to_string())


is_negative_qty = df["Quantity"] < 0
is_positive_qty = df["Quantity"] > 0
is_zero_price = df["Price"] == 0

internal_zero_neg = (~is_c_invoice) & (~is_admin) & is_negative_qty & is_zero_price
free_positive_zero = (~is_c_invoice) & (~is_admin) & is_positive_qty & is_zero_price

print("\n" + "=" * 60)
print("ZERO-PRICE SUBTYPES")
print("=" * 60)

print(f"Zero-price, positive quantity: {free_positive_zero.sum():,}")
print(f"Zero-price, negative quantity: {internal_zero_neg.sum():,}")

# ============================================================
# FREE ITEMS (ZERO-PRICE, POSITIVE QTY) VS STOCKCODE TYPE
# ============================================================

print("\n" + "=" * 60)
print("FREE ITEMS (ZERO-PRICE, POSITIVE QTY) VS STOCKCODE TYPE")
print("=" * 60)

# Crosstab: special vs normal stock codes for true free items
print(pd.crosstab(
    is_special_stock[free_positive_zero],
    columns="count"
))

print("\nTop StockCodes in free items:")
print(df.loc[free_positive_zero, "StockCode"].value_counts().head(20).to_string())

print("\nTop Descriptions in free items:")
print(df.loc[free_positive_zero, "Description"].value_counts().head(20).to_string())

# ============================================================
# DCGS / GIFT STOCKCODE DEEP DIVE
# ============================================================

is_dcgs = df["StockCode"].str.contains("DCGS", case=False, na=False)
is_gift = df["StockCode"].str.contains("gift", case=False, na=False)


def print_code_family_summary(label, mask):
    subset = df.loc[mask].copy()

    print("\n" + "=" * 60)
    print(f"{label} STOCKCODE DEEP DIVE")
    print("=" * 60)

    print(f"Total rows: {len(subset):,}")
    print(f"Unique StockCodes: {subset['StockCode'].nunique():,}")

    print("\nInvoice type distribution:")
    print(subset["InvoiceNo"].astype(str).str[0].value_counts().sort_index().to_string())

    qty_bucket = pd.Series(
        pd.NA,
        index=subset.index,
        dtype="object"
    )
    qty_bucket.loc[subset["Quantity"] < 0] = "< 0"
    qty_bucket.loc[subset["Quantity"] == 0] = "= 0"
    qty_bucket.loc[subset["Quantity"] > 0] = "> 0"

    price_bucket = pd.Series(
        pd.NA,
        index=subset.index,
        dtype="object"
    )
    price_bucket.loc[subset["Price"] < 0] = "< 0"
    price_bucket.loc[subset["Price"] == 0] = "= 0"
    price_bucket.loc[subset["Price"] > 0] = "> 0"

    print("\nQuantity bucket distribution:")
    print(qty_bucket.value_counts().sort_index().to_string())

    print("\nPrice bucket distribution:")
    print(price_bucket.value_counts().sort_index().to_string())

    print("\nQuantity x Price cross-tab:")
    print(pd.crosstab(qty_bucket, price_bucket).to_string())

    customer_present = subset["CustomerID"].notna()
    print("\nCustomerID present vs missing:")
    print(customer_present.value_counts().rename(index={True: "present", False: "missing"}).to_string())

    print("\nTop countries:")
    print(subset["Country"].value_counts().head(10).to_string())

    print("\nTop StockCodes:")
    print(subset["StockCode"].value_counts().head(20).to_string())

    print("\nTop Descriptions:")
    print(subset["Description"].value_counts().head(20).to_string())


print_code_family_summary("DCGS", is_dcgs)
print_code_family_summary("GIFT", is_gift)


# ============================================================
# HYPOTHESIS TEST: DESCRIPTION PRESENCE (Q > 0 & P > 0)
# ============================================================

print("\n" + "=" * 60)
print("HYPOTHESIS TEST: DESCRIPTION PRESENCE (Q > 0 & P > 0)")
print("=" * 60)

# Masks
gift_paid = is_gift & (df["Quantity"] > 0) & (df["Price"] > 0)
dcgs_paid = is_dcgs & (df["Quantity"] > 0) & (df["Price"] > 0)

# -----------------------
# GIFT CHECK
# -----------------------
gift_subset = df.loc[gift_paid]

missing_gift_desc = gift_subset["Description"].isna() | (gift_subset["Description"].str.strip() == "")

print("\nGIFT (Q > 0 & P > 0)")
print(f"Total rows: {len(gift_subset):,}")
print(f"Missing/blank descriptions: {missing_gift_desc.sum():,}")

if missing_gift_desc.sum() > 0:
    print("\nExamples (GIFT missing description):")
    print(gift_subset.loc[missing_gift_desc, ["StockCode", "Description"]].head(10).to_string(index=False))


# -----------------------
# DCGS CHECK
# -----------------------
dcgs_subset = df.loc[dcgs_paid]

missing_dcgs_desc = dcgs_subset["Description"].isna() | (dcgs_subset["Description"].str.strip() == "")

print("\nDCGS (Q > 0 & P > 0)")
print(f"Total rows: {len(dcgs_subset):,}")
print(f"Missing/blank descriptions: {missing_dcgs_desc.sum():,}")

# Check your "ebay / update" theory
is_ebay_update = dcgs_subset["Description"].str.lower().isin(["ebay", "update"])

print(f"Rows with description 'ebay' or 'update': {is_ebay_update.sum():,}")

print("\nExamples (DCGS ebay/update):")
print(dcgs_subset.loc[is_ebay_update, ["StockCode", "Description"]].head(10).to_string(index=False))


print("\n" + "=" * 60)
print("DCGS SAMPLE (Q > 0, P > 0)")
print("=" * 60)

dcgs_paid = df.loc[
    is_dcgs & (df["Quantity"] > 0) & (df["Price"] > 0)
]

# Random sample (more useful than top rows)
print(dcgs_paid.sample(20)[
    ["InvoiceNo", "StockCode", "Description", "Quantity", "Price"]
].to_string(index=False))

print("\nPrice distribution:")
print(dcgs_paid["Price"].describe())

print("\nQuantity distribution:")
print(dcgs_paid["Quantity"].describe())

normal_products = df.loc[
    (~is_dcgs) &
    (df["Quantity"] > 0) &
    (df["Price"] > 0)
]

overlap = set(dcgs_paid["Description"]).intersection(set(normal_products["Description"]))

print(f"\nOverlap in descriptions with normal sales: {len(overlap)}")
print(list(overlap)[:10])

non_dcgs_gift_special = (
    is_special_stock &
    ~is_dcgs &
    ~is_gift
)

print("\n" + "=" * 60)
print("NON-DCGS/GIFT SPECIAL STOCKCODES")
print("=" * 60)

print(df.loc[non_dcgs_gift_special, "StockCode"].value_counts().head(20))

print("\n" + "=" * 60)
print("PROVISIONAL DATASET DECISIONS")
print("=" * 60)

print("1. Exclude admin/accounting rows:")
print("   - InvoiceNo starts with 'A'")

print("\n2. Cancellations / return invoices:")
print("   - InvoiceNo starts with 'C'")
print("   - Note: one C-invoice row with positive quantity should be reviewed separately")

print("\n3. Internal inventory adjustments:")
print("   - Quantity < 0 and Price = 0")
print("   - Not C-invoice and not A-invoice")

print("\n4. Free items / promotions:")
print("   - Quantity > 0 and Price = 0")
print("   - Not C-invoice and not A-invoice")

print("\n5. Gift voucher rows:")
print("   - StockCode contains 'gift'")
print("   - Treat separately from product sales")

print("\n6. DCGS rows:")
print("   - StockCode contains 'DCGS'")
print("   - Treat separately from main retail sales")

print("\n7. Remaining non-DCGS/GIFT special StockCodes:")
print("   - Review as financial/operational rows")
print("   - Examples: POST, DOT, M, BANK CHARGES, ADJUST, AMAZONFEE")