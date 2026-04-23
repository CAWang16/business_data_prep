import pandas as pd
import os

data_location = '../data/raw'

df2_sheets = pd.read_excel(os.path.join(data_location, "online_retail_II.xlsx"), sheet_name=None, dtype={"Customer ID": str})

df2 = pd.concat(df2_sheets.values(), ignore_index=True)


print("=" * 60)
print("1. SHAPE")
print(df2.shape)

print("\n" + "=" * 60)
print("2. COLUMN NAMES & DTYPES")
print(df2.dtypes)

print("\n" + "=" * 60)
print("3. FIRST 5 ROWS")
print(df2.head())

print("\n" + "=" * 60)
print("4. MISSING VALUES (count & %)")
missing = df2.isnull().sum()
missing_pct = (missing / len(df2) * 100).round(2)
print(pd.DataFrame({"count": missing, "%": missing_pct}))

print("\n" + "=" * 60)
print("5. DUPLICATE ROWS")
print(f"Duplicate rows: {df2.duplicated().sum()}")

print("\n" + "=" * 60)
print("6. BASIC STATISTICS (numeric columns)")
print(df2.describe())

print("\n" + "=" * 60)
print("7. UNIQUE VALUE COUNTS (categorical columns)")
for col in ["Country", "StockCode", "Description"]:
    print(f"  {col}: {df2[col].nunique()} unique values")

print("\n" + "=" * 60)
print("8. TOP 10 COUNTRIES BY ORDER VOLUME")
print(df2["Country"].value_counts().head(10))

print("\n" + "=" * 60)
print("9. DATE RANGE")
df2["InvoiceDate"] = pd.to_datetime(df2["InvoiceDate"])
print(f"  Min: {df2['InvoiceDate'].min()}")
print(f"  Max: {df2['InvoiceDate'].max()}")

print("\n" + "=" * 60)
print("10. NEGATIVE / ZERO QUANTITY (returns / errors)")
print(f"  Quantity <= 0: {(df2['Quantity'] <= 0).sum()} rows")
print(f"  Price <= 0:    {(df2['Price'] <= 0).sum()} rows")


print("\n" + "=" * 60)
print("11. CLEANING")

before = len(df2)
print(f"  Rows before cleaning: {before:,}")

df2 = df2.drop_duplicates()
after_dedup = len(df2)
print(f"  After dropping duplicates: {after_dedup:,}  (removed {before - after_dedup:,})")

df2 = df2[df2["Quantity"] > 0]
after_qty = len(df2)
print(f"  After removing Quantity <= 0: {after_qty:,}  (removed {after_dedup - after_qty:,})")

df2 = df2[df2["Price"] > 0]
after_price = len(df2)
print(f"  After removing Price <= 0:    {after_price:,}  (removed {after_qty - after_price:,})")

print(f"\n  Total removed: {before - after_price:,}  ({(before - after_price) / before * 100:.2f}%)")
print(f"  Final row count: {after_price:,}")


import numpy as np
import matplotlib.pyplot as plt


df2["TotalPrice"] = df2["Quantity"] * df2["Price"]

print("\n" + "=" * 60)
print("12. TOTAL PRICE STATS")
print(df2["TotalPrice"].describe().round(2))
print(f"  Skewness: {df2['TotalPrice'].skew():.2f}")

print("\n" + "=" * 60)
print("12b. TRACING SKEW RECORDS")

# IQR-based outlier boundary
Q1 = df2["TotalPrice"].quantile(0.25)
Q3 = df2["TotalPrice"].quantile(0.75)
IQR = Q3 - Q1
upper_fence = Q3 + 1.5 * IQR

skew_records = df2[df2["TotalPrice"] > upper_fence].sort_values("TotalPrice", ascending=False)
print(f"  IQR upper fence: £{upper_fence:.2f}")
print(f"  Outlier rows:    {len(skew_records):,}  ({len(skew_records)/len(df2)*100:.2f}% of data)")
print(f"\n  Top 20 skew-driving records:")
print(skew_records[["Invoice", "Description", "Quantity", "Price", "TotalPrice", "Customer ID", "Country"]].head(20).to_string(index=False))

skew_records.to_csv("skew_outliers.csv", index=False)
print(f"\n  Full outlier list saved to skew_outliers.csv  ({len(skew_records):,} rows)")

fig, axes = plt.subplots(1, 2, figsize=(12, 4))

axes[0].hist(df2["TotalPrice"], bins=100, color="steelblue", edgecolor="none")
axes[0].set_title("TotalPrice (raw)")
axes[0].set_xlabel("TotalPrice")
axes[0].set_ylabel("Frequency")

axes[1].hist(np.log1p(df2["TotalPrice"]), bins=100, color="darkorange", edgecolor="none")
axes[1].set_title("log1p(TotalPrice)")
axes[1].set_xlabel("log1p(TotalPrice)")
axes[1].set_ylabel("Frequency")

plt.tight_layout()
plt.savefig("totalprice_distribution.png", dpi=150)
print("\n  Plot saved to totalprice_distribution.png")

# ── EXPORT ───────────────────────────────────────────────────────────────────

df2.to_csv("online_retail_II_cleaned.csv", index=False)
print("\nExported to online_retail_II_cleaned.csv")

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION A: MARKET & GEOGRAPHIC INSIGHTS
# ═══════════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 60)
print("A1. UK vs NON-UK ORDER SHARE")
uk_count = (df2["Country"] == "United Kingdom").sum()
total = len(df2)
print(f"  UK orders:     {uk_count:,}  ({uk_count/total*100:.1f}%)")
print(f"  Non-UK orders: {total - uk_count:,}  ({(total - uk_count)/total*100:.1f}%)")

print("\n" + "=" * 60)
print("A2. HIGH-VALUE OUTLIERS BY COUNTRY (TotalPrice > 99th percentile)")
threshold = df2["TotalPrice"].quantile(0.99)
outliers = df2[df2["TotalPrice"] > threshold]
print(f"  Threshold (99th pct): £{threshold:.2f}")
print(outliers["Country"].value_counts().head(10))
print(f"\n  Avg TotalPrice of outliers by country:")
print(outliers.groupby("Country")["TotalPrice"].mean().sort_values(ascending=False).head(10).round(2))

# Plot: revenue by country (ex-UK to see secondary markets)
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

top_countries = df2["Country"].value_counts().head(10)
top_countries.plot(kind="bar", ax=axes[0], color="steelblue")
axes[0].set_title("Top 10 Countries by Order Volume")
axes[0].set_xlabel("Country")
axes[0].set_ylabel("Number of Orders")
axes[0].tick_params(axis="x", rotation=45)

non_uk = df2[df2["Country"] != "United Kingdom"]
non_uk_revenue = non_uk.groupby("Country")["TotalPrice"].sum().sort_values(ascending=False).head(10)
non_uk_revenue.plot(kind="bar", ax=axes[1], color="darkorange")
axes[1].set_title("Top 10 Non-UK Countries by Revenue")
axes[1].set_xlabel("Country")
axes[1].set_ylabel("Total Revenue (£)")
axes[1].tick_params(axis="x", rotation=45)

plt.tight_layout()
plt.savefig("geographic_insights.png", dpi=150)
print("\n  Plot saved to geographic_insights.png")

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION B: PRICING & REVENUE STRATEGY
# ═══════════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 60)
print("B1. IMPULSE BUY RANGE (TotalPrice percentiles)")
for p in [25, 50, 75, 90, 95, 99]:
    print(f"  {p}th pct: £{df2['TotalPrice'].quantile(p/100):.2f}")

print("\n" + "=" * 60)
print("B2. WHOLESALE / VIP CUSTOMERS (top 1% by spend)")
customer_spend = df2.groupby("Customer ID")["TotalPrice"].sum().sort_values(ascending=False)
vip_threshold = customer_spend.quantile(0.99)
vip_customers = customer_spend[customer_spend >= vip_threshold]
print(f"  VIP threshold (99th pct): £{vip_threshold:,.2f}")
print(f"  Number of VIP customers:  {len(vip_customers)}")
print(f"  VIP revenue share:        {vip_customers.sum() / customer_spend.sum() * 100:.1f}%")
print(f"\n  Top 10 customers by total spend:")
print(customer_spend.head(10).apply(lambda x: f"£{x:,.2f}"))

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION C: SEASONALITY & TIMING
# ═══════════════════════════════════════════════════════════════════════════════

df2["Month"]      = df2["InvoiceDate"].dt.month
df2["DayOfWeek"]  = df2["InvoiceDate"].dt.day_name()
df2["Hour"]       = df2["InvoiceDate"].dt.hour

print("\n" + "=" * 60)
print("C1. BEST SEASON (orders by month)")
month_orders = df2["Month"].value_counts().sort_index()
month_names  = {1:"Jan",2:"Feb",3:"Mar",4:"Apr",5:"May",6:"Jun",
                7:"Jul",8:"Aug",9:"Sep",10:"Oct",11:"Nov",12:"Dec"}
for m, cnt in month_orders.items():
    print(f"  {month_names[m]}: {cnt:,}")

print("\n" + "=" * 60)
print("C2. BEST DAY OF WEEK")
day_order = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
dow = df2["DayOfWeek"].value_counts().reindex(day_order)
print(dow)

print("\n" + "=" * 60)
print("C3. BEST HOUR OF DAY")
print(df2["Hour"].value_counts().sort_index())

fig, axes = plt.subplots(1, 3, figsize=(16, 4))

month_orders.plot(kind="bar", ax=axes[0], color="steelblue")
axes[0].set_title("Orders by Month")
axes[0].set_xlabel("Month")
axes[0].set_ylabel("Orders")
axes[0].set_xticks(range(12))
axes[0].set_xticklabels(list(month_names.values()), rotation=45)

dow.plot(kind="bar", ax=axes[1], color="darkorange")
axes[1].set_title("Orders by Day of Week")
axes[1].set_xlabel("Day")
axes[1].set_ylabel("Orders")
axes[1].tick_params(axis="x", rotation=45)

df2["Hour"].value_counts().sort_index().plot(kind="bar", ax=axes[2], color="seagreen")
axes[2].set_title("Orders by Hour of Day")
axes[2].set_xlabel("Hour")
axes[2].set_ylabel("Orders")

plt.tight_layout()
plt.savefig("seasonality_timing.png", dpi=150)
print("\n  Plot saved to seasonality_timing.png")

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION D: OPERATIONAL HEALTH — RETURN RATE BY MONTH
# ═══════════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 60)
print("D1. RETURN RATE BY MONTH")

# Re-load raw (pre-clean) to get cancellations
raw = pd.concat(df2_sheets.values(), ignore_index=True)
raw["InvoiceDate"] = pd.to_datetime(raw["InvoiceDate"])
raw["Month"] = raw["InvoiceDate"].dt.month

cancellations = raw[raw["Quantity"] < 0].groupby("Month").size()
all_orders    = raw.groupby("Month").size()
return_rate   = (cancellations / all_orders * 100).round(2)

for m, rate in return_rate.items():
    print(f"  {month_names[m]}: {rate:.2f}%  ({cancellations.get(m, 0):,} returns / {all_orders[m]:,} total)")

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION E: PRODUCT AFFINITY — TOP CO-PURCHASED PAIRS
# ═══════════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 60)
print("E1. TOP 10 PRODUCT PAIRS (co-purchased in same invoice)")

from itertools import combinations

basket = df2.groupby("Invoice")["Description"].apply(list)
pair_counts = {}
for items in basket:
    unique_items = list(set(items))
    if len(unique_items) >= 2:
        for pair in combinations(sorted(unique_items), 2):
            pair_counts[pair] = pair_counts.get(pair, 0) + 1

top_pairs = sorted(pair_counts.items(), key=lambda x: x[1], reverse=True)[:10]
for pair, count in top_pairs:
    print(f"  [{count:,}x]  {pair[0]}  +  {pair[1]}")