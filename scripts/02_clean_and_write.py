import sqlite3
import pandas as pd

DB_FILE = "database/retail.db"
RAW_TABLE = "online_retail"
CLEAN_TABLE = "online_retail_clean"
EXCLUDED_TABLE = "online_retail_excluded"

# ============================================================
# LOAD RAW DATA
# ============================================================

conn = sqlite3.connect(DB_FILE)
df = pd.read_sql(f"SELECT * FROM {RAW_TABLE}", conn)
conn.close()

# Standardize column names
df = df.rename(columns={
    "Customer ID": "CustomerID",
    "Invoice": "InvoiceNo"
})

df["InvoiceNo"] = df["InvoiceNo"].astype(str).str.strip()
df["StockCode"] = df["StockCode"].astype(str).str.strip()

print("=" * 60)
print("02 — CLEAN AND WRITE")
print("=" * 60)
print(f"Raw rows loaded: {len(df):,}")

# ============================================================
# DEFINE EXCLUSION MASKS
# Based on decisions from 01_split_decision_eda.py
# ============================================================

# 1. Admin/accounting rows (InvoiceNo starts with 'A')
is_admin = df["InvoiceNo"].str.startswith("A")

# 2. Cancellation/return invoices (InvoiceNo starts with 'C')
is_cancellation = df["InvoiceNo"].str.startswith("C")

# 3. Internal inventory adjustments (negative qty, zero price, not C or A invoice)
is_internal_adjustment = (
    ~is_cancellation &
    ~is_admin &
    (df["Quantity"] < 0) &
    (df["Price"] == 0)
)

# 4. Free items / promotions (positive qty, zero price, not C or A invoice)
is_free_item = (
    ~is_cancellation &
    ~is_admin &
    (df["Quantity"] > 0) &
    (df["Price"] == 0)
)

# 5. Gift voucher rows (StockCode contains 'gift', case-insensitive)
is_gift = df["StockCode"].str.contains("gift", case=False, na=False)

# 6. DCGS rows (StockCode contains 'DCGS')
is_dcgs = df["StockCode"].str.contains("DCGS", case=False, na=False)

# 7. Other special StockCodes (not standard 5-digit or 5-digit+1-2 letter pattern)
#    excludes gift and DCGS which are already flagged above
is_special_stock = ~df["StockCode"].str.match(r"^\d{5}([A-Za-z]{1,2})?$")
is_other_special = is_special_stock & ~is_gift & ~is_dcgs

# Combined exclusion mask
is_excluded = (
    is_admin |
    is_cancellation |
    is_internal_adjustment |
    is_free_item |
    is_gift |
    is_dcgs |
    is_other_special
)

# ============================================================
# REPORT EXCLUSION COUNTS
# ============================================================

print("\n" + "=" * 60)
print("EXCLUSION BREAKDOWN")
print("=" * 60)
print(f"1. Admin rows (A-invoice):              {is_admin.sum():>8,}")
print(f"2. Cancellations (C-invoice):           {is_cancellation.sum():>8,}")
print(f"3. Internal adjustments (neg qty/free): {is_internal_adjustment.sum():>8,}")
print(f"4. Free items (zero price):             {is_free_item.sum():>8,}")
print(f"5. Gift voucher rows:                   {is_gift.sum():>8,}")
print(f"6. DCGS rows:                           {is_dcgs.sum():>8,}")
print(f"7. Other special StockCodes:            {is_other_special.sum():>8,}")
print(f"{'—' * 45}")
print(f"Total excluded (unique rows):           {is_excluded.sum():>8,}")
print(f"Rows remaining:                         {(~is_excluded).sum():>8,}")

# ============================================================
# SPLIT INTO CLEAN AND EXCLUDED
# ============================================================

df_excluded = df[is_excluded].copy()
df_excluded["ExclusionReason"] = "other"
df_excluded.loc[is_admin, "ExclusionReason"] = "admin_invoice"
df_excluded.loc[is_cancellation, "ExclusionReason"] = "cancellation"
df_excluded.loc[is_internal_adjustment, "ExclusionReason"] = "internal_adjustment"
df_excluded.loc[is_free_item, "ExclusionReason"] = "free_item"
df_excluded.loc[is_gift, "ExclusionReason"] = "gift_voucher"
df_excluded.loc[is_dcgs, "ExclusionReason"] = "dcgs"
df_excluded.loc[is_other_special, "ExclusionReason"] = "special_stockcode"

df_clean = df[~is_excluded].copy()

# ============================================================
# ADDITIONAL CLEANING ON CLEAN SUBSET
# ============================================================

# Parse InvoiceDate
df_clean["InvoiceDate"] = pd.to_datetime(df_clean["InvoiceDate"], errors="coerce")

# Drop rows where date parsing failed
bad_dates = df_clean["InvoiceDate"].isna().sum()
if bad_dates > 0:
    print(f"\nDropping {bad_dates:,} rows with unparseable InvoiceDate")
    df_clean = df_clean[df_clean["InvoiceDate"].notna()]

# Normalize text fields
df_clean["Description"] = df_clean["Description"].astype(str).str.strip().str.upper()
df_clean["Country"] = df_clean["Country"].astype(str).str.strip()

# Fill missing descriptions using most common description per StockCode
desc_lookup = (
    df_clean[df_clean["Description"].notna()]
    .groupby("StockCode")["Description"]
    .agg(lambda x: x.mode().iloc[0] if not x.mode().empty else None)
)
df_clean["Description"] = df_clean.apply(
    lambda row: desc_lookup.get(row["StockCode"], row["Description"])
    if pd.isna(row["Description"]) or row["Description"] == "NAN"
    else row["Description"],
    axis=1
)

# Standardize known country name inconsistencies
country_map = {
    "EIRE": "Ireland",
    "Unspecified": None,  # will become NaN — exclude or keep depending on use case
}
df_clean["Country"] = df_clean["Country"].replace(country_map)

# Flag rows with missing CustomerID (kept in clean set — useful for product analysis)
df_clean["HasCustomerID"] = df_clean["CustomerID"].notna()

# Derive useful columns
df_clean["Revenue"] = df_clean["Quantity"] * df_clean["Price"]
df_clean["InvoiceYear"] = df_clean["InvoiceDate"].dt.year
df_clean["InvoiceMonth"] = df_clean["InvoiceDate"].dt.month
df_clean["InvoiceDay"] = df_clean["InvoiceDate"].dt.day
df_clean["InvoiceDayOfWeek"] = df_clean["InvoiceDate"].dt.day_name()
df_clean["InvoiceHour"] = df_clean["InvoiceDate"].dt.hour

# ============================================================
# FINAL CLEAN DATASET SUMMARY
# ============================================================

print("\n" + "=" * 60)
print("CLEAN DATASET SUMMARY")
print("=" * 60)
print(f"Rows: {len(df_clean):,}")
print(f"Columns: {df_clean.shape[1]}")
print(f"\nDate range: {df_clean['InvoiceDate'].min()} → {df_clean['InvoiceDate'].max()}")
print(f"Unique customers (with ID): {df_clean[df_clean['HasCustomerID']]['CustomerID'].nunique():,}")
print(f"Unique invoices: {df_clean['InvoiceNo'].nunique():,}")
print(f"Unique products: {df_clean['StockCode'].nunique():,}")
print(f"Unique countries: {df_clean['Country'].nunique():,}")
print(f"\nMissing CustomerID: {(~df_clean['HasCustomerID']).sum():,} ({(~df_clean['HasCustomerID']).mean():.2%})")
print(f"Total Revenue: £{df_clean['Revenue'].sum():,.2f}")

# ============================================================
# WRITE TO DATABASE
# ============================================================

print("\n" + "=" * 60)
print("WRITING TO DATABASE")
print("=" * 60)

conn = sqlite3.connect(DB_FILE)

df_clean.to_sql(CLEAN_TABLE, conn, if_exists="replace", index=False)
print(f"Written '{CLEAN_TABLE}': {len(df_clean):,} rows")

df_excluded.to_sql(EXCLUDED_TABLE, conn, if_exists="replace", index=False)
print(f"Written '{EXCLUDED_TABLE}': {len(df_excluded):,} rows")

conn.close()

print("\nDone. Two tables written to retail.db:")
print(f"  - {CLEAN_TABLE}  → use this for all analysis")
print(f"  - {EXCLUDED_TABLE} → audit trail of removed rows")
print("\nTo use in R:")
print(f"  con <- dbConnect(RSQLite::SQLite(), 'database/retail.db')")
print(f"  df <- dbReadTable(con, '{CLEAN_TABLE}')")
