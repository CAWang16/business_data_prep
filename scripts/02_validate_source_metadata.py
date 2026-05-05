import sqlite3
import pandas as pd

DB_FILE = "database/retail.db"
RAW_TABLE = "online_retail"

# Connecting to database
conn = sqlite3.connect(DB_FILE)
df = pd.read_sql(f"SELECT * FROM {RAW_TABLE}", conn)
conn.close()

# Standardize column names
df = df.rename(columns={
    "Customer ID": "CustomerID",
    "Invoice": "InvoiceNo"
})

# printing basic header and sanity checks
print("=" * 60)
print("RAW DATA METADATA VALIDATION")
print("=" * 60)
print(f"Rows: {len(df):,}")
print(f"Columns: {len(df.columns)}")
print("\nColumn names:")
print(df.columns.tolist())

##########################################################################

# --- INVOICE NO VALIDATION ---
print("\n" + "=" * 60)
print("INVOICE NO FORMAT VALIDATION")
print("=" * 60)

# Ensure InvoiceNo is string
df["InvoiceNo"] = df["InvoiceNo"].astype(str)

# Define pattern: optional 'C' followed by 6 digits
valid_pattern = r"^C?\d{6}$"

# Check validity
valid_mask = df["InvoiceNo"].str.match(valid_pattern)

valid_count = valid_mask.sum()
invalid_count = (~valid_mask).sum()

print(f"Valid InvoiceNo format:   {valid_count:,}")
print(f"Invalid InvoiceNo format: {invalid_count:,}")
print(f"Invalid rate: {invalid_count / len(df):.6%}")

# Show examples of invalid values (if any)
if invalid_count > 0:
    print("\nExamples of invalid InvoiceNo:")
    print(df.loc[~valid_mask, "InvoiceNo"].head(10).tolist())

# inspect invalid values
if invalid_count > 0:
    print("\nInvalid InvoiceNo rows:")
    cols_to_show = [
        "InvoiceNo", "StockCode", "Description", "Quantity",
        "InvoiceDate", "Price", "CustomerID", "Country"
    ]
    print(df.loc[~valid_mask, cols_to_show].to_string(index=False))

    print("\nInvalid InvoiceNo summary:")
    print("Unique StockCodes:", df.loc[~valid_mask, "StockCode"].nunique())
    print("Unique Countries:", df.loc[~valid_mask, "Country"].nunique())
    print("Unique CustomerIDs:", df.loc[~valid_mask, "CustomerID"].nunique())

    print("\nConclusion:")
    print("Rows with InvoiceNo starting with 'A' are accounting adjustments "
        "('Adjust bad debt'), not standard retail transactions.")
    
##########################################################################

# --- CUSTOMER ID VALIDATION ---
print("\n" + "=" * 60)
print("CUSTOMER ID FORMAT VALIDATION")
print("=" * 60)

# Count missing
missing_customer = df["CustomerID"].isna().sum()

# Convert non-missing to string for pattern check
customer_str = df["CustomerID"].dropna().astype(int).astype(str)

# Define valid pattern: exactly 5 digits
valid_pattern = r"^\d{5}$"

valid_customer_mask = customer_str.str.match(valid_pattern)

valid_customer_count = valid_customer_mask.sum()
invalid_customer_count = (~valid_customer_mask).sum()

print(f"Missing CustomerID: {missing_customer:,} ({missing_customer / len(df):.2%})")
print(f"Valid CustomerID format:   {valid_customer_count:,}")
print(f"Invalid CustomerID format: {invalid_customer_count:,}")

# Inspect invalid values if any
if invalid_customer_count > 0:
    print("\nExamples of invalid CustomerID:")
    print(customer_str.loc[~valid_customer_mask].head(10).tolist())

    print("\nInvalid CustomerID rows:")
    cols_to_show = [
        "InvoiceNo", "StockCode", "Description", "Quantity",
        "InvoiceDate", "Price", "CustomerID", "Country"
    ]
    print(df.loc[df["CustomerID"].notna() & 
                 (~df["CustomerID"].astype(int).astype(str).str.match(valid_pattern)),
                 cols_to_show].head(10).to_string(index=False))

    print("\nConclusion:")
    print("Some CustomerID values do not conform to the expected 5-digit format.")

else:
    print("\nConclusion:")
    print("All non-missing CustomerID values conform to the expected 5-digit format.")

##########################################################################

# --- QUANTITY & PRICE VALIDATION ---
print("\n" + "=" * 60)
print("QUANTITY & PRICE VALIDATION")
print("=" * 60)

# Check dtypes
print("Dtypes:")
print(df[["Quantity", "Price"]].dtypes)

# Basic numeric checks (in case of hidden issues)
quantity_non_numeric = pd.to_numeric(df["Quantity"], errors="coerce").isna().sum()
price_non_numeric = pd.to_numeric(df["Price"], errors="coerce").isna().sum()

print(f"\nNon-numeric Quantity values: {quantity_non_numeric:,}")
print(f"Non-numeric Price values:    {price_non_numeric:,}")

# Quantity breakdown
qty_neg = (df["Quantity"] < 0).sum()
qty_zero = (df["Quantity"] == 0).sum()
qty_pos = (df["Quantity"] > 0).sum()

print("\nQuantity breakdown:")
print(f"Quantity < 0:  {qty_neg:,}")
print(f"Quantity = 0:  {qty_zero:,}")
print(f"Quantity > 0:  {qty_pos:,}")

# Price breakdown
price_neg = (df["Price"] < 0).sum()
price_zero = (df["Price"] == 0).sum()
price_pos = (df["Price"] > 0).sum()

print("\nPrice breakdown:")
print(f"Price < 0:  {price_neg:,}")
print(f"Price = 0:  {price_zero:,}")
print(f"Price > 0:  {price_pos:,}")

# Inspect suspicious rows
if price_neg > 0:
    print("\nExamples of negative Price rows:")
    cols_to_show = [
        "InvoiceNo", "StockCode", "Description",
        "Quantity", "Price", "CustomerID", "Country"
    ]
    print(df[df["Price"] < 0][cols_to_show].head(10).to_string(index=False))

if qty_zero > 0:
    print("\nExamples of Quantity = 0 rows:")
    print(df[df["Quantity"] == 0][cols_to_show].head(10).to_string(index=False))

# Summary conclusions
print("\nConclusion:")

print("- Quantity < 0 primarily indicates returns/cancellations, but may also include adjustment-related rows.")
print("- Price = 0 represents non-revenue transactions (free items or system-related rows).")
print("- Quantity > 0 and Price > 0 represent candidate standard sales.")


if price_neg > 0:
    print("- Negative Price values are administrative bad-debt adjustments and should be excluded from transactional analysis.")

if qty_zero > 0:
    print("- Quantity = 0 rows exist and may represent data anomalies.")

##########################################################################

# --- INVOICE DATE VALIDATION ---
print("\n" + "=" * 60)
print("INVOICE DATE VALIDATION")
print("=" * 60)

# Attempt to parse InvoiceDate
parsed_dates = pd.to_datetime(df["InvoiceDate"], errors="coerce")

invalid_date_count = parsed_dates.isna().sum()
valid_date_count = parsed_dates.notna().sum()

print(f"Valid InvoiceDate values:   {valid_date_count:,}")
print(f"Invalid InvoiceDate values: {invalid_date_count:,}")
print(f"Invalid date rate: {invalid_date_count / len(df):.6%}")

if invalid_date_count > 0:
    print("\nExamples of invalid InvoiceDate values:")
    print(df.loc[parsed_dates.isna(), "InvoiceDate"].head(10).tolist())

print("\nDate range:")
print(f"Min InvoiceDate: {parsed_dates.min()}")
print(f"Max InvoiceDate: {parsed_dates.max()}")

print("\nConclusion:")
if invalid_date_count == 0:
    print("All InvoiceDate values were parsed successfully.")
else:
    print("Some InvoiceDate values could not be parsed and should be investigated.")

##########################################################################

# --- STOCKCODE VALIDATION / PROFILING ---
print("\n" + "=" * 60)
print("STOCKCODE VALIDATION / PROFILING")
print("=" * 60)

# Ensure string
df["StockCode"] = df["StockCode"].astype(str)

# Pattern: exactly 5 digits
numeric_pattern = r"^\d{5}$"

numeric_mask = df["StockCode"].str.match(numeric_pattern)

numeric_count = numeric_mask.sum()
non_numeric_count = (~numeric_mask).sum()

print(f"5-digit numeric StockCodes:   {numeric_count:,}")
print(f"Non-numeric StockCodes:       {non_numeric_count:,}")
print(f"Non-numeric rate: {non_numeric_count / len(df):.2%}")

# Unique StockCodes
unique_stockcodes = df["StockCode"].nunique()
print(f"\nTotal unique StockCodes: {unique_stockcodes:,}")

# Unique non-numeric StockCodes
unique_non_numeric = df.loc[~numeric_mask, "StockCode"].nunique()
print(f"Unique non-numeric StockCodes: {unique_non_numeric:,}")

# StockCodes that are neither 5-digit numeric nor 5-digit + trailing letter
numeric_plus_suffix_pattern = r"^\d{5}[A-Za-z]$"
numeric_plus_suffix_mask = df["StockCode"].str.match(numeric_plus_suffix_pattern)

special_mask = ~(numeric_mask | numeric_plus_suffix_mask)
special_count = special_mask.sum()
unique_special = df.loc[special_mask, "StockCode"].nunique()

print(f"\nSpecial StockCode rows: {special_count:,}")
print(f"Unique special StockCodes: {unique_special:,}")

if unique_special > 0:
    print("\nExamples of special StockCodes:")
    print(df.loc[special_mask, "StockCode"].drop_duplicates().head(20).tolist())

    print("\nTop special StockCodes by frequency:")
    print(df.loc[special_mask, "StockCode"].value_counts().head(20))

# Optional: how many descriptions per StockCode (sanity check)
desc_per_stock = (
    df.groupby("StockCode")["Description"]
      .nunique(dropna=True)
)

ambiguous_desc_count = (desc_per_stock > 1).sum()

print(f"\nStockCodes with multiple descriptions: {ambiguous_desc_count:,}")

print("\nConclusion:")
print("- StockCode is not strictly a 5-digit numeric field.")
print("- Many StockCodes follow a 5-digit+suffix pattern and appear to be product variants or subtypes.")
print("- A much smaller set of special StockCodes fall outside both standard patterns and likely represent service, adjustment, discount, or system entries.")
print("- StockCode should be treated as a categorical identifier, not a strictly numeric ID.")

##########################################################################

# --- SPECIAL STOCKCODE DEEP CHECK ---
print("\n" + "=" * 60)
print("SPECIAL STOCKCODE ANALYSIS")
print("=" * 60)

special_df = df[special_mask]

# Description consistency
desc_per_special = (
    special_df.groupby("StockCode")["Description"]
    .nunique(dropna=True)
)

print("\nDescriptions per special StockCode:")
print(desc_per_special.to_string())

# Price behavior
price_summary = (
    special_df.groupby("StockCode")["Price"]
    .agg(["min", "max", "mean"])
)

print("\nPrice summary per special StockCode:")
print(price_summary.to_string())

# CustomerID missingness
customer_missing = (
    special_df.groupby("StockCode")["CustomerID"]
    .apply(lambda x: x.isna().mean())
)

print("\n% missing CustomerID per special StockCode:")
print(customer_missing.round(3).to_string())

# Invoice patterns
invoice_prefix = (
    special_df["InvoiceNo"]
    .str[0]
    .value_counts()
)

print("\nInvoice prefix distribution (special StockCodes):")
print(invoice_prefix)

print("\nConclusion:")
print("- Special StockCodes are heterogeneous.")
print("- Some clearly represent administrative or service entries (e.g., POST, DOT, M, BANK CHARGES, ADJUST, AMAZONFEE).")
print("- Others behave more like nonstandard product or catalog codes.")
print("- These codes should be reviewed separately from standard product StockCodes in downstream cleaning and EDA.")

##########################################################################

# --- COUNTRY VALIDATION / CONSISTENCY ---
print("\n" + "=" * 60)
print("COUNTRY VALIDATION / CONSISTENCY")
print("=" * 60)

# Missing / blank checks
missing_country = df["Country"].isna().sum()
blank_country = (df["Country"].astype(str).str.strip() == "").sum()
unspecified_country = (df["Country"].astype(str).str.strip() == "Unspecified").sum()

print(f"Missing Country values: {missing_country:,}")
print(f"Blank Country values:   {blank_country:,}")
print(f"Unspecified Country rows: {unspecified_country:,} ({unspecified_country / len(df):.2%})")

# Unique countries
unique_countries = df["Country"].nunique(dropna=True)
print(f"\nUnique countries: {unique_countries:,}")

print("\nTop 20 countries by row count:")
print(df["Country"].value_counts().head(20).to_string())

# Sorted country list for consistency inspection
country_list = sorted(df["Country"].dropna().astype(str).str.strip().unique())

print("\nAll unique countries:")
for country in country_list:
    print(country)

print("\nConclusion:")
if missing_country == 0 and blank_country == 0:
    print("Country values have no missing or blank entries.")
else:
    print("Some Country values are missing or blank and should be reviewed.")

print("However, some values (e.g., 'Unspecified') represent coded unknown locations rather than true country labels.")
print("There are also naming inconsistencies (e.g., 'EIRE' instead of 'Ireland').")
print("Country should be treated as a categorical field.")
print("Country standardization decisions should be handled in downstream split-EDA / cleaning, not in this validation file.")





##########################################################################

# --- DESCRIPTION MISSINGNESS / NORMALIZATION NOTE ---
print("\n" + "=" * 60)
print("DESCRIPTION MISSINGNESS / NORMALIZATION NOTE")
print("=" * 60)

missing_description = df["Description"].isna().sum()
print(f"Missing Description rows: {missing_description:,} ({missing_description / len(df):.2%})")

print("\nConclusion:")
print("- Description has missing values and should be treated as a text-cleaning problem, not a strict format-validation problem.")
print("- Description standardization steps such as trimming whitespace, case normalization, and safe filling via StockCode belong in downstream split-EDA / cleaning.")


print("\n" + "=" * 60)
print("OVERALL VALIDATION SUMMARY")
print("=" * 60)
print("- Core transaction fields are structurally valid.")
print("- InvoiceNo has 6 special A-prefixed accounting-adjustment rows.")
print("- CustomerID issues are due to missingness, not invalid formatting.")
print("- StockCode is a mixed identifier system, not a strictly numeric product ID.")
print("- Country has no blanks/NaNs but includes coded unknown and naming inconsistencies.")
print("- Description requires downstream normalization/filling rather than strict validation.")