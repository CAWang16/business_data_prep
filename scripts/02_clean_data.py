"""
02_clean_data.py

Purpose:
    Clean and standardize the Description column in the Online Retail II data.

    This script focuses on one major cleaning task:
        1. Load the raw retail data from the SQLite database.
        2. Fill missing Description values when StockCode has exactly one known
           description.
        3. Detect operational/noise descriptions such as "found", "lost", etc.
        4. Build a canonical StockCode -> Description map using the most frequent
           non-noise description.
        5. Apply the canonical description across the full dataset.
        6. Save a checkpoint file for the next cleaning stage.

    Later steps will create masks for row types such as cancellations, admin rows,
    free items, gift vouchers, DCGS rows, shipping fees, and clean sales.
"""

from pathlib import Path
import sqlite3

import pandas as pd


# -----------------------------------------------------------------------------
# Project paths
# -----------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATABASE_PATH = PROJECT_ROOT / "database" / "retail.db"
PROCESSED_DATA_DIR = PROJECT_ROOT / "data" / "processed"
CLEAN_DATABASE_PATH = PROJECT_ROOT / "database" / "clean_retail.db"


# -----------------------------------------------------------------------------
# Load data
# -----------------------------------------------------------------------------

def load_raw_retail_data(database_path: Path = DATABASE_PATH) -> pd.DataFrame:
    """
    Load the raw Online Retail II table from the SQLite database.
    """
    if not database_path.exists():
        raise FileNotFoundError(
            f"Database file not found: {database_path}\n"
            "Run scripts/setup_db.py first to create database/retail.db."
        )

    with sqlite3.connect(database_path) as conn:
        return pd.read_sql_query("SELECT * FROM online_retail", conn)


# -----------------------------------------------------------------------------
# Column normalization
# -----------------------------------------------------------------------------

def normalize_column_names(df: pd.DataFrame) -> pd.DataFrame:
    """
    Standardize column names to snake_case for consistency and easier coding.

    Example:
        InvoiceNo   -> invoice_no
        CustomerID  -> customer_id
        StockCode   -> stock_code
    """
    df = df.copy()

    df.columns = (
        df.columns
        .str.strip()
        .str.replace(" ", "_", regex=False)
        .str.replace(r"(?<!^)(?=[A-Z])", "_", regex=True)
        .str.replace(r"_+", "_", regex=True)
        .str.lower()
    )

    # Online Retail II source columns can differ slightly depending on the load
    # path. For example, the source uses "Invoice" rather than "InvoiceNo", and
    # "Customer ID" can normalize awkwardly because of the all-caps ID suffix.
    rename_map = {
        "invoice": "invoice_no",
        "customer_i_d": "customer_id",
        "customer_id": "customer_id",
    }

    df = df.rename(columns=rename_map)

    return df


# -----------------------------------------------------------------------------
# Description cleaning helpers
# -----------------------------------------------------------------------------

def normalize_description_text(df: pd.DataFrame) -> pd.DataFrame:
    """
    Make description easier to work with by trimming whitespace and treating
    empty strings as missing values.
    """
    df = df.copy()

    df["description"] = df["description"].astype("string").str.strip()
    df.loc[df["description"].eq(""), "description"] = pd.NA

    return df


def fill_missing_descriptions_from_unique_stockcode(df: pd.DataFrame) -> pd.DataFrame:
    """
    Fill missing description values only when a stock_code has exactly one known
    description elsewhere in the dataset.

    This is the safest description-fill rule because there is no ambiguity.
    """
    df = df.copy()

    missing_description = df["description"].isna()

    description_counts = (
        df.dropna(subset=["description"])
        .groupby("stock_code")["description"]
        .nunique()
    )

    stockcodes_with_one_description = description_counts[description_counts == 1].index

    stockcode_to_description = (
        df[
            df["stock_code"].isin(stockcodes_with_one_description)
            & df["description"].notna()
        ]
        .drop_duplicates(subset=["stock_code"])
        .set_index("stock_code")["description"]
    )

    mapped_descriptions = df["stock_code"].map(stockcode_to_description)
    fill_mask = missing_description & mapped_descriptions.notna()

    df["description_filled"] = False
    df.loc[fill_mask, "description"] = mapped_descriptions.loc[fill_mask]
    df.loc[fill_mask, "description_filled"] = True

    return df


def is_noise_description(series: pd.Series) -> pd.Series:
    """
    Identify operational/noise descriptions that should not be used as canonical
    product descriptions.

    The list is intentionally simple and expandable as more cases are found.
    """
    noise_words = [
        "found",
        "lost",
        "damages",
        "check",
        "missing",
        "mixed",
        "damaged",
        "amazon",
        "adjustment",
    ]

    series_lower = series.astype("string").str.lower().str.strip()

    exact_noise = series_lower.isin(noise_words)
    question_mark_noise = series_lower.str.contains(r"\?", na=False)

    return exact_noise | question_mark_noise


def build_most_frequent_description_map(df: pd.DataFrame) -> pd.DataFrame:
    """
    Build a stock_code -> canonical description map using the most frequent
    non-noise description for each stock_code.

    This map is built from the full dataset, not only from rows with missing
    descriptions. That lets us fix rows such as description == "found" whenever
    the same stock_code has a valid product description elsewhere.
    """
    valid_descriptions = df[
        df["description"].notna()
        & ~df["is_noise_description"]
    ].copy()

    description_frequency = (
        valid_descriptions
        .groupby(["stock_code", "description"])
        .size()
        .reset_index(name="description_count")
        .sort_values(
            ["stock_code", "description_count", "description"],
            ascending=[True, False, True],
        )
    )

    canonical_map = (
        description_frequency
        .drop_duplicates(subset=["stock_code"], keep="first")
        .rename(columns={"description": "canonical_description"})
    )

    num_valid_descriptions = (
        valid_descriptions
        .groupby("stock_code")["description"]
        .nunique()
        .rename("num_valid_descriptions")
        .reset_index()
    )

    canonical_map = canonical_map.merge(
        num_valid_descriptions,
        on="stock_code",
        how="left",
    )

    return canonical_map


def apply_description_standardization(
    df: pd.DataFrame,
    standardization_map: pd.DataFrame,
) -> pd.DataFrame:
    """
    Apply canonical descriptions across the full dataset.

    Important distinction:
        - description_in_standardization_map tells us whether a row's stock_code
          had a canonical description available.
        - description_standardized tells us whether the row's description value
          actually changed.
    """
    df = df.copy()

    # Preserve original description for auditing.
    df["description_original"] = df["description"]

    stockcode_to_canonical = standardization_map.set_index("stock_code")[
        "canonical_description"
    ]

    df["canonical_description"] = df["stock_code"].map(stockcode_to_canonical)

    standardize_mask = df["canonical_description"].notna()
    df["description_in_standardization_map"] = standardize_mask

    changed_mask = standardize_mask & (
        df["description"].isna()
        | df["description"].ne(df["canonical_description"])
    )

    df["description_standardized"] = False
    df["description_standardization_reason"] = pd.NA

    missing_mask = changed_mask & df["description"].isna()
    noise_mask = changed_mask & df["description"].notna() & df["is_noise_description"]
    variant_mask = changed_mask & df["description"].notna() & ~df["is_noise_description"]

    df.loc[
        missing_mask,
        "description_standardization_reason",
    ] = "filled_missing_from_canonical_stockcode_description"

    df.loc[
        noise_mask,
        "description_standardization_reason",
    ] = "replaced_noise_with_canonical_stockcode_description"

    df.loc[
        variant_mask,
        "description_standardization_reason",
    ] = "standardized_variant_to_canonical_stockcode_description"

    # Apply canonical descriptions globally for consistency.
    df.loc[standardize_mask, "description"] = df.loc[
        standardize_mask,
        "canonical_description",
    ]

    # Only mark rows as standardized if the value actually changed.
    df.loc[changed_mask, "description_standardized"] = True

    return df


# -----------------------------------------------------------------------------
# Dataset decision masks
# -----------------------------------------------------------------------------

def add_dataset_decision_masks(df: pd.DataFrame) -> pd.DataFrame:
    """
    Add reusable boolean masks for the major row types identified during EDA.

    These masks do not remove rows. They only label rows so that later we can
    split the dataset into clean sales, cancellations, admin/accounting rows,
    free items, gift vouchers, DCGS rows, shipping fees, and review rows.
    """
    df = df.copy()

    invoice_no = df["invoice_no"].astype("string")
    stock_code = df["stock_code"].astype("string")

    # 1. Admin/accounting rows
    df["is_admin_invoice"] = invoice_no.str.startswith("A", na=False)

    # 2. Cancellations / return invoices
    df["is_cancellation_invoice"] = invoice_no.str.startswith("C", na=False)

    # 3. Internal inventory adjustments
    df["is_inventory_adjustment"] = (
        (df["quantity"] < 0)
        & (df["price"] == 0)
        & ~df["is_admin_invoice"]
        & ~df["is_cancellation_invoice"]
    )

    # 4. Free items / promotions
    df["is_free_item"] = (
        (df["quantity"] > 0)
        & (df["price"] == 0)
        & ~df["is_admin_invoice"]
        & ~df["is_cancellation_invoice"]
    )

    # 5. Gift voucher rows
    df["is_gift_voucher"] = stock_code.str.contains("gift", case=False, na=False)

    # 6. DCGS rows
    df["is_dcgs"] = stock_code.str.contains("DCGS", case=False, na=False)

    # 7. Shipping / carriage fee rows
    df["is_shipping_fee"] = stock_code.isin(["DOT", "POST", "C2"])

    # 8. Manual rows
    df["is_manual"] = stock_code.eq("M")

    # 9. Other known financial / operational special codes
    df["is_other_special_code"] = stock_code.isin([
        "BANK CHARGES",
        "ADJUST",
        "AMAZONFEE",
        "D",
        "S",
        "TEST001",
        "TEST002",
    ])

    # Manual rows that are not already captured by the stronger exclusion rules.
    # These may be product-like sales and can be kept with a flag later.
    df["is_manual_product_like_sale"] = (
        df["is_manual"]
        & ~df["is_admin_invoice"]
        & ~df["is_cancellation_invoice"]
        & ~df["is_inventory_adjustment"]
        & ~df["is_free_item"]
        & ~df["is_gift_voucher"]
        & ~df["is_dcgs"]
        & ~df["is_shipping_fee"]
        & ~df["is_other_special_code"]
    )

    # Main clean product sales candidate.
    # This keeps regular positive-quantity, positive-price product rows.
    # Manual rows are excluded here and saved separately as manual_product_sales.
    df["is_clean_product_sale_candidate"] = (
        (df["quantity"] > 0)
        & (df["price"] > 0)
        & ~df["is_admin_invoice"]
        & ~df["is_cancellation_invoice"]
        & ~df["is_inventory_adjustment"]
        & ~df["is_free_item"]
        & ~df["is_gift_voucher"]
        & ~df["is_dcgs"]
        & ~df["is_shipping_fee"]
        & ~df["is_manual"]
        & ~df["is_other_special_code"]
    )

    return df


# -----------------------------------------------------------------------------
# Reporting helpers
# -----------------------------------------------------------------------------

def print_description_standardization_summary(
    df_before_standardization: pd.DataFrame,
    df_after_standardization: pd.DataFrame,
) -> None:
    """
    Print the final audit block for description standardization.
    """
    rows_in_standardization_map = df_after_standardization[
        "description_in_standardization_map"
    ].sum()

    rows_actually_changed = df_after_standardization[
        "description_standardized"
    ].sum()

    missing_before_apply = df_before_standardization["description"].isna().sum()
    missing_after_apply = df_after_standardization["description"].isna().sum()

    missing_filled = (
        df_after_standardization["description_standardization_reason"]
        .eq("filled_missing_from_canonical_stockcode_description")
        .sum()
    )

    noise_replaced = (
        df_after_standardization["description_standardization_reason"]
        .eq("replaced_noise_with_canonical_stockcode_description")
        .sum()
    )

    variants_standardized = (
        df_after_standardization["description_standardization_reason"]
        .eq("standardized_variant_to_canonical_stockcode_description")
        .sum()
    )

    print("\nApplied description standardization")
    print("------------------------------------")
    print(f"Rows in standardization map:        {rows_in_standardization_map:,}")
    print(f"Rows actually changed:              {rows_actually_changed:,}")
    print(f"Missing descriptions before apply:  {missing_before_apply:,}")
    print(f"Missing descriptions after apply:   {missing_after_apply:,}")
    print(f"Missing descriptions filled:        {missing_filled:,}")
    print(f"Noise descriptions replaced:        {noise_replaced:,}")
    print(f"Valid variants standardized:        {variants_standardized:,}")


def print_dataset_mask_summary(df: pd.DataFrame) -> None:
    """
    Print row counts for each dataset decision mask.
    """
    mask_columns = [
        "is_admin_invoice",
        "is_cancellation_invoice",
        "is_inventory_adjustment",
        "is_free_item",
        "is_gift_voucher",
        "is_dcgs",
        "is_shipping_fee",
        "is_manual",
        "is_manual_product_like_sale",
        "is_other_special_code",
        "is_clean_product_sale_candidate",
    ]

    print("\nDataset decision mask summary")
    print("-----------------------------")
    for col in mask_columns:
        print(f"{col}: {df[col].sum():,}")


# -----------------------------------------------------------------------------
# Dataset mask descriptions
# -----------------------------------------------------------------------------

def print_dataset_mask_descriptions() -> None:
    """
    Print a brief explanation of what each dataset mask represents.
    """
    print("\nDataset definitions")
    print("--------------------")
    print("is_admin_invoice: Accounting/admin rows (InvoiceNo starts with 'A')")
    print("is_cancellation_invoice: Returns/cancellations (InvoiceNo starts with 'C')")
    print("is_inventory_adjustment: Internal adjustments (quantity < 0 and price = 0)")
    print("is_free_item: Promotional/free items (quantity > 0 and price = 0)")
    print("is_gift_voucher: Gift-related stock codes")
    print("is_dcgs: DCGS-related stock codes")
    print("is_shipping_fee: Shipping/carriage charges (DOT, POST, C2)")
    print("is_manual: Manual stock code entries (stock_code == 'M')")
    print("is_manual_product_like_sale: Manual rows treated as product-like sales")
    print("is_other_special_code: Other operational/financial codes (BANK CHARGES, etc.)")
    print("is_clean_product_sale_candidate: Core retail sales (positive qty & price, excluding special cases)")


# -----------------------------------------------------------------------------
# Excel checkpoint helper for large datasets
# -----------------------------------------------------------------------------

def save_excel_checkpoint(
    df: pd.DataFrame,
    output_path: Path,
    changed_sample_rows: int = 20_000,
) -> None:
    """
    Save a smaller Excel checkpoint for human review.

    The full cleaned dataset has over 1 million rows and is too large/slow to
    reliably write as an Excel workbook. This review file uses a hybrid sample:

        1. One representative row per stock_code for broad product coverage.
        2. Up to changed_sample_rows rows where description actually changed,
           so we can inspect cleaning/standardization examples.

    The full processed dataset should be saved to SQLite in the next step.
    """
    # One row per stock_code gives broad product coverage for review.
    one_per_stock_code = (
        df.sort_values(["stock_code", "invoice_date", "invoice_no"])
        .groupby("stock_code", dropna=False)
        .head(1)
    )

    # Rows that actually changed are the most important to inspect.
    changed_rows = df[df["description_standardized"]].head(changed_sample_rows)

    review_df = (
        pd.concat([one_per_stock_code, changed_rows], ignore_index=True)
        .drop_duplicates()
        .sort_values(["stock_code", "invoice_date", "invoice_no"])
        .copy()
    )

    with pd.ExcelWriter(output_path, engine="openpyxl") as writer:
        review_df.to_excel(
            writer,
            sheet_name="review_sample",
            index=False,
        )

        mask_summary = pd.DataFrame({
            "metric": [
                "total_rows",
                "review_rows_saved",
                "unique_stock_codes_in_review",
                "changed_rows_requested",
                "rows_in_standardization_map",
                "rows_actually_changed",
                "missing_descriptions_after_standardization",
                "is_clean_product_sale_candidate",
                "is_cancellation_invoice",
                "is_admin_invoice",
                "is_inventory_adjustment",
                "is_free_item",
                "is_gift_voucher",
                "is_dcgs",
                "is_shipping_fee",
                "is_manual_product_like_sale",
                "is_other_special_code",
            ],
            "value": [
                len(df),
                len(review_df),
                int(review_df["stock_code"].nunique(dropna=False)),
                changed_sample_rows,
                int(df["description_in_standardization_map"].sum()),
                int(df["description_standardized"].sum()),
                int(df["description"].isna().sum()),
                int(df["is_clean_product_sale_candidate"].sum()),
                int(df["is_cancellation_invoice"].sum()),
                int(df["is_admin_invoice"].sum()),
                int(df["is_inventory_adjustment"].sum()),
                int(df["is_free_item"].sum()),
                int(df["is_gift_voucher"].sum()),
                int(df["is_dcgs"].sum()),
                int(df["is_shipping_fee"].sum()),
                int(df["is_manual_product_like_sale"].sum()),
                int(df["is_other_special_code"].sum()),
            ],
        })

        mask_summary.to_excel(
            writer,
            sheet_name="summary",
            index=False,
        )

# -----------------------------------------------------------------------------
# Save cleaned datasets to SQLite
# -----------------------------------------------------------------------------

def save_to_clean_retail_db(df: pd.DataFrame, db_path: Path) -> None:
    """
    Save dataset splits into a structured SQLite database.
    """
    with sqlite3.connect(db_path) as conn:
        # Full cleaned dataset (with all flags)
        df.to_sql("cleaned_retail_all", conn, if_exists="replace", index=False)

        # Core datasets
        df[df["is_clean_product_sale_candidate"]].to_sql(
            "clean_product_sales", conn, if_exists="replace", index=False
        )

        df[df["is_manual_product_like_sale"]].to_sql(
            "manual_product_sales", conn, if_exists="replace", index=False
        )

        df[df["is_cancellation_invoice"]].to_sql(
            "cancellations", conn, if_exists="replace", index=False
        )

        df[df["is_admin_invoice"]].to_sql(
            "admin_invoices", conn, if_exists="replace", index=False
        )

        df[df["is_inventory_adjustment"]].to_sql(
            "inventory_adjustments", conn, if_exists="replace", index=False
        )

        df[df["is_free_item"]].to_sql(
            "free_items", conn, if_exists="replace", index=False
        )

        df[df["is_gift_voucher"]].to_sql(
            "gift_vouchers", conn, if_exists="replace", index=False
        )

        df[df["is_dcgs"]].to_sql(
            "dcgs_rows", conn, if_exists="replace", index=False
        )

        df[df["is_shipping_fee"]].to_sql(
            "shipping_fees", conn, if_exists="replace", index=False
        )

        df[df["is_other_special_code"]].to_sql(
            "other_special_rows", conn, if_exists="replace", index=False
        )


# -----------------------------------------------------------------------------
# Script runner
# -----------------------------------------------------------------------------

def main() -> None:
    """
    Run the description cleaning and standardization pipeline.
    """
    PROCESSED_DATA_DIR.mkdir(parents=True, exist_ok=True)

    retail = load_raw_retail_data()
    retail = normalize_column_names(retail)

    retail = normalize_description_text(retail)
    retail = fill_missing_descriptions_from_unique_stockcode(retail)

    retail["is_noise_description"] = is_noise_description(retail["description"])

    standardization_map = build_most_frequent_description_map(retail)


    retail_before_standardization = retail.copy()
    retail = apply_description_standardization(retail, standardization_map)

    print_description_standardization_summary(
        retail_before_standardization,
        retail,
    )

    retail = add_dataset_decision_masks(retail)
    print_dataset_mask_summary(retail)
    print_dataset_mask_descriptions()

    output_path = PROCESSED_DATA_DIR / "retail_with_standardized_descriptions_review.xlsx"
    save_excel_checkpoint(retail, output_path)

    print(f"Saved Excel review checkpoint to: {output_path}")

    save_to_clean_retail_db(retail, CLEAN_DATABASE_PATH)
    print(f"Saved cleaned datasets to SQLite DB: {CLEAN_DATABASE_PATH}")


if __name__ == "__main__":
    main()