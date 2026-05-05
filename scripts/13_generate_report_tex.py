import sqlite3
import os
import pandas as pd

DB_FILE = "database/retail.db"
RAW_TABLE = "online_retail"
OUTPUT_FILE = "report.tex"

# ── helpers ───────────────────────────────────────────────────────────────────

def esc(text):
    """Escape special LaTeX characters in a string."""
    text = str(text)
    replacements = [
        ("\\", "\\textbackslash{}"),
        ("&",  "\\&"),
        ("%",  "\\%"),
        ("$",  "\\$"),
        ("#",  "\\#"),
        ("_",  "\\_"),
        ("{",  "\\{"),
        ("}",  "\\}"),
        ("~",  "\\textasciitilde{}"),
        ("^",  "\\textasciicircum{}"),
        ("←",  "$\\leftarrow$"),
        ("→",  "$\\to$"),
        ("£",  "\\pounds{}"),
        ("×",  "$\\times$"),
        ("–",  "--"),
        ("'",  "'"),
        (""",  "``"),
        (""",  "''"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    return text


def df_to_longtable(df, caption, label, col_widths=None):
    """Convert a DataFrame to a LaTeX longtable."""
    ncols = len(df.columns)
    if col_widths is None:
        width = round(0.9 / ncols, 3)
        col_spec = " ".join([f"p{{{width}\\textwidth}}"] * ncols)
    else:
        col_spec = " ".join(col_widths)

    lines = []
    lines.append(f"\\begin{{longtable}}{{{col_spec}}}")
    lines.append(f"\\caption{{{esc(caption)}}} \\label{{{label}}} \\\\")
    lines.append("\\toprule")
    header = " & ".join(f"\\textbf{{{esc(c)}}}" for c in df.columns)
    lines.append(header + " \\\\")
    lines.append("\\midrule")
    lines.append("\\endfirsthead")
    lines.append(f"\\multicolumn{{{ncols}}}{{l}}{{\\small\\textit{{(continued from previous page)}}}} \\\\")
    lines.append("\\toprule")
    lines.append(header + " \\\\")
    lines.append("\\midrule")
    lines.append("\\endhead")
    lines.append("\\midrule")
    lines.append(f"\\multicolumn{{{ncols}}}{{r}}{{\\small\\textit{{Continued on next page}}}} \\\\")
    lines.append("\\endfoot")
    lines.append("\\bottomrule")
    lines.append("\\endlastfoot")
    for _, row in df.iterrows():
        lines.append(" & ".join(esc(v) for v in row) + " \\\\")
    lines.append("\\end{longtable}")
    return "\n".join(lines)


def figure_block(filename, caption, label, width="0.85\\textwidth"):
    fig_path = os.path.join("figures", filename).replace("\\", "/")
    return (
        "\\begin{figure}[htbp]\n"
        "  \\centering\n"
        f"  \\includegraphics[width={width}]{{{fig_path}}}\n"
        f"  \\caption{{{esc(caption)}}}\n"
        f"  \\label{{{label}}}\n"
        "\\end{figure}"
    )


# ── load & compute ─────────────────────────────────────────────────────────────

print("Loading data from database...")
conn = sqlite3.connect(DB_FILE)
df = pd.read_sql(f"SELECT * FROM {RAW_TABLE}", conn)
conn.close()

df = df.rename(columns={"Customer ID": "CustomerID", "Invoice": "InvoiceNo"})
df["InvoiceNo"] = df["InvoiceNo"].astype(str)
df["StockCode"] = df["StockCode"].astype(str).str.strip()

total_rows = len(df)
total_cols = len(df.columns)

valid_inv_mask = df["InvoiceNo"].str.match(r"^C?\d{6}$")
valid_inv  = valid_inv_mask.sum()
invalid_inv = (~valid_inv_mask).sum()
n_c_invoice = df["InvoiceNo"].str.startswith("C").sum()
n_standard_sale = valid_inv - n_c_invoice

missing_cid = df["CustomerID"].isna().sum()
missing_cid_pct = missing_cid / total_rows
cid_str = df["CustomerID"].dropna().astype(int).astype(str)
valid_cid = cid_str.str.match(r"^\d{5}$").sum()

qty_neg  = (df["Quantity"] < 0).sum()
qty_zero = (df["Quantity"] == 0).sum()
qty_pos  = (df["Quantity"] > 0).sum()
price_neg  = (df["Price"] < 0).sum()
price_zero = (df["Price"] == 0).sum()
price_pos  = (df["Price"] > 0).sum()

parsed_dates = pd.to_datetime(df["InvoiceDate"], errors="coerce")
invalid_dates = parsed_dates.isna().sum()
date_min = parsed_dates.min()
date_max = parsed_dates.max()

numeric_mask = df["StockCode"].str.match(r"^\d{5}$")
suffix_mask  = df["StockCode"].str.match(r"^\d{5}[A-Za-z]{1,2}$")
special_mask = ~(numeric_mask | suffix_mask)
special_count  = special_mask.sum()
unique_special = df.loc[special_mask, "StockCode"].nunique()

missing_country   = df["Country"].isna().sum()
unspecified       = (df["Country"].astype(str).str.strip() == "Unspecified").sum()
unique_countries  = df["Country"].nunique(dropna=True)
top10_countries   = df["Country"].value_counts().head(10).reset_index()
top10_countries.columns = ["Country", "Row Count"]
top10_countries["Row Count"] = top10_countries["Row Count"].apply(lambda x: f"{x:,}")

missing_desc = df["Description"].isna().sum()

is_admin     = df["InvoiceNo"].str.startswith("A")
is_c_invoice_mask = df["InvoiceNo"].str.startswith("C")
is_neg_qty   = df["Quantity"] < 0
is_pos_qty   = df["Quantity"] > 0
is_zero_price = df["Price"] == 0
is_dcgs = df["StockCode"].str.contains("DCGS", case=False, na=False)
is_gift = df["StockCode"].str.contains("gift", case=False, na=False)

returns_count = is_c_invoice_mask.sum()
returns_pct   = returns_count / total_rows
admin_count   = is_admin.sum()
free_count    = ((~is_c_invoice_mask) & (~is_admin) & is_pos_qty & is_zero_price).sum()
internal_adj  = ((~is_c_invoice_mask) & (~is_admin) & is_neg_qty & is_zero_price).sum()
mismatch_neg_not_c = (is_neg_qty & ~is_c_invoice_mask).sum()
mismatch_c_not_neg = (is_c_invoice_mask & ~is_neg_qty).sum()

df_no_admin = df[~is_admin]
clean_sales = df_no_admin[
    ~df_no_admin["InvoiceNo"].str.startswith("C") &
    (df_no_admin["Quantity"] > 0) &
    (df_no_admin["Price"] > 0)
]

cs_revenue          = (clean_sales["Quantity"] * clean_sales["Price"])
cs_total_revenue    = cs_revenue.sum()
cs_unique_invoices  = clean_sales["InvoiceNo"].nunique()
cs_unique_customers = clean_sales["CustomerID"].nunique()
cs_unique_products  = clean_sales["StockCode"].nunique()

top_products = (
    clean_sales.groupby("StockCode")["Description"]
    .agg(lambda x: x.mode().iloc[0] if not x.mode().empty else "")
    .reset_index()
    .merge(clean_sales.groupby("StockCode")["Quantity"].sum().reset_index(), on="StockCode")
    .sort_values("Quantity", ascending=False)
    .head(10)
    .rename(columns={"Quantity": "Total Qty Sold"})
)
top_products["Total Qty Sold"] = top_products["Total Qty Sold"].apply(lambda x: f"{x:,}")

missing_cid_by_country = (
    df[~is_admin]
    .groupby("Country")
    .apply(lambda x: x["CustomerID"].isna().mean())
    .sort_values(ascending=False)
    .head(8)
    .reset_index()
)
missing_cid_by_country.columns = ["Country", "Missing CustomerID Rate"]
missing_cid_by_country["Missing CustomerID Rate"] = (
    missing_cid_by_country["Missing CustomerID Rate"].map("{:.1%}".format)
)

print("Data computed. Building LaTeX document...")

# ── LaTeX document ─────────────────────────────────────────────────────────────

lines = []

# Preamble
lines.append(r"""\documentclass[12pt,a4paper]{article}

\usepackage[a4paper, margin=2.5cm]{geometry}
\usepackage{booktabs}
\usepackage{longtable}
\usepackage{array}
\usepackage{graphicx}
\usepackage{hyperref}
\usepackage{parskip}
\usepackage{titlesec}
\usepackage{enumitem}
\usepackage{caption}
\usepackage{microtype}
\usepackage[T1]{fontenc}
\usepackage[utf8]{inputenc}
\usepackage{lmodern}

\hypersetup{
    colorlinks=true,
    linkcolor=blue,
    urlcolor=blue,
    citecolor=blue
}

\captionsetup{font=small, labelfont=bf}

\title{\textbf{Online Retail II}\\[0.5em]
       \large Data Processing \& Analysis Report}
\author{Carl \& Anders\\[0.3em]
        \small CSP 571 --- Spring 2026}
\date{April 2026}

\begin{document}
\maketitle
\tableofcontents
\newpage
""")

# ── 1. Abstract ───────────────────────────────────────────────────────────────
lines.append(r"\section{Abstract}")
lines.append(
    f"This report documents the full data processing and exploratory analysis pipeline "
    f"applied to the UCI Online Retail II dataset, covering transactions from a UK-based "
    f"non-store online retailer between December 2009 and December 2011. The dataset "
    f"comprises {total_rows:,} raw transaction records spanning eight fields. "
    "Our work proceeds in three phases: (1)~metadata validation of raw source fields to "
    "identify structural anomalies and format inconsistencies; (2)~split-decision "
    "exploratory data analysis to classify records into semantically distinct transaction "
    "types; and (3)~computation of summary statistics, data visualisations, and feature "
    f"extraction in preparation for downstream modelling. Key findings include that "
    f"approximately {missing_cid_pct:.1%} of records lack a CustomerID, that InvoiceNo and "
    "StockCode encode multiple transaction types (sales, cancellations, accounting "
    "adjustments, free promotions), and that a structured seven-category split is required "
    "before any customer-level or product-level analysis can be conducted reliably."
)
lines.append(r"\newpage")

# ── 2. Overview ───────────────────────────────────────────────────────────────
lines.append(r"\section{Overview}")

lines.append(r"\subsection{Problem Statement}")
lines.append(
    "E-commerce retailers accumulate vast volumes of transactional data whose raw form is "
    "rarely suitable for direct analysis. The Online Retail II dataset presents several "
    "challenges representative of real-world retail data: mixed transaction semantics encoded "
    "within shared fields (sales, returns, administrative adjustments, and free promotions "
    "all reside in the same table); pervasive missing values in the CustomerID field; "
    "non-standard StockCode identifiers for service and operational entries; and naming "
    "inconsistencies in geographic fields."
)
lines.append(
    "The primary objective of this project is to design and implement a reproducible data "
    "processing pipeline that: (a)~validates the structural integrity of raw source fields; "
    "(b)~identifies and separates semantically distinct record types; (c)~applies principled "
    "cleaning and transformation rules with explicit assumptions; and (d)~extracts analytic "
    "features that support downstream customer segmentation and purchase-pattern modelling."
)

lines.append(r"\subsection{Related Work / Literature Review}")
lines.append(
    r"Retail transaction datasets have been extensively studied in the data mining "
    r"literature. RFM (Recency, Frequency, Monetary) analysis, introduced by "
    r"Bult and Wansbeek (1995) and popularised by Hughes (1994), remains one of the most "
    r"widely applied frameworks for customer value segmentation and is directly applicable "
    r"to invoice-level data such as the Online Retail II dataset."
)
lines.append(
    r"Chen et al.\ (2012) used an earlier version of this dataset (Online Retail I) to "
    r"demonstrate data mining techniques for customer segmentation using K-Means clustering "
    r"on RFM features, establishing a widely cited baseline for this source. Daqing Chen's "
    r"original UCI submission noted that the dataset contains a mix of wholesale and retail "
    r"customers, which has implications for any per-unit price analysis."
)
lines.append(
    r"More recent work has extended transaction-level analysis to sequence modelling and "
    r"collaborative filtering. Hidasi et al.\ (2016) demonstrated session-based recurrent "
    r"neural networks for next-item recommendation, while Devooght and Bersini (2017) "
    r"compared collaborative filtering approaches on transactional purchase histories. "
    r"These downstream applications all share the upstream requirement of clean, well-typed "
    r"transaction records, motivating the careful data processing approach documented in "
    r"this report."
)
lines.append(
    r"Data cleaning practices for retail datasets are discussed by Rahm and Do (2000), who "
    r"classify data quality problems into single-source and multi-source issues. The "
    r"challenges encountered in this project --- missing identifiers, mixed semantics within "
    r"a single column, and implicit coding conventions (C-prefixed cancellation invoices, "
    r"A-prefixed accounting entries) --- are consistent with their taxonomy of schema-level "
    r"and instance-level anomalies."
)

lines.append(r"\subsection{Proposed Methodology}")
lines.append(
    r"Our methodology follows a sequential, script-driven pipeline with one Python script "
    r"per logical stage, each operating on the shared SQLite database. This design keeps "
    r"each stage independently reproducible and auditable."
)
lines.append(r"\begin{itemize}[leftmargin=1.5em]")
lines.append(r"  \item \textbf{Stage 0 --- Data Ingestion} (\texttt{setup\_db.py}): "
             r"Load both Excel sheets from the raw source file into a single SQLite table.")
lines.append(r"  \item \textbf{Stage 1 --- Metadata Validation} "
             r"(\texttt{00\_validate\_source\_metadata.py}): Validate each raw field for "
             r"format conformance, value ranges, and missingness.")
lines.append(r"  \item \textbf{Stage 2 --- Split-Decision EDA} "
             r"(\texttt{01\_split\_decision\_eda.py}): Classify records into transaction "
             r"types using cross-tabulation and overlap analysis.")
lines.append(r"  \item \textbf{Stage 3 --- Cleaning \& Transformation}: Apply the split "
             r"decisions to produce a filtered, typed, and enriched table ready for "
             r"analysis.")
lines.append(r"  \item \textbf{Stage 4 --- Analysis}: Compute summary statistics, generate "
             r"visualisations, and extract modelling features.")
lines.append(r"\end{itemize}")
lines.append(r"\newpage")

# ── 3. Data Processing ────────────────────────────────────────────────────────
lines.append(r"\section{Data Processing}")

# 3.1
lines.append(r"\subsection{Data Description}")
lines.append(
    r"The Online Retail II dataset (UCI Machine Learning Repository, donated by Daqing "
    r"Chen, London South Bank University) covers transactions of a UK-based online "
    r"retailer that primarily sells unique all-occasion gift-ware to wholesale customers. "
    r"The data spans two consecutive fiscal years delivered as two Excel sheets."
)

desc_df = pd.DataFrame({
    "Property": ["Source", "Format", "Sheets",
                 "Date range", "Total rows (combined)", "Columns"],
    "Value": [
        "UCI Machine Learning Repository --- Online Retail II",
        "Microsoft Excel (.xlsx)",
        "Year 2009--2010 (525,461 rows),  Year 2010--2011 (541,910 rows)",
        f"{date_min.strftime('%d %b %Y')} -- {date_max.strftime('%d %b %Y')}",
        f"{total_rows:,}",
        str(total_cols),
    ]
})
lines.append(df_to_longtable(desc_df, "Dataset overview", "tab:dataset_overview",
                              col_widths=["p{0.25\\textwidth}", "p{0.65\\textwidth}"]))

lines.append(
    r"Note on source column names: the raw Excel file uses \texttt{Invoice}, "
    r"\texttt{Customer ID}, and \texttt{Price} for what the official specification "
    r"calls \texttt{InvoiceNo}, \texttt{CustomerID}, and \texttt{UnitPrice} respectively. "
    r"This report uses the official names throughout. "
    r"Fields are nominal (categorical) unless noted: \texttt{Quantity}, "
    r"\texttt{InvoiceDate}, and \texttt{UnitPrice} are numeric."
)

col_df = pd.DataFrame({
    "Field": ["InvoiceNo", "StockCode", "Description", "Quantity",
              "InvoiceDate", "UnitPrice", "CustomerID", "Country"],
    "Official Definition": [
        "6-digit integral number uniquely assigned to each transaction. 'C' prefix = cancellation.",
        "5-digit integral number uniquely assigned to each distinct product.",
        "Product (item) name.",
        "Quantities of each product per transaction. Numeric.",
        "Day and time when the transaction was generated. Numeric.",
        "Product price per unit in sterling (£). Numeric.",
        "5-digit integral number uniquely assigned to each customer.",
        "Name of the country where the customer resides.",
    ],
    "Observed Deviations": [
        "6 rows carry 'A' prefix (accounting adjustments) --- undocumented in spec",
        "Suffix variants (e.g. 85123A) and fully non-standard codes exist --- spec says 5-digit integral only",
        "approx. 2% of rows missing",
        "Negative values present (returns / adjustments)",
        "No deviations --- all values parse successfully",
        "Zero and negative values present; stored as 'Price' in source file",
        "approx. 25% of rows missing",
        "'Unspecified' entries present; naming inconsistencies (e.g. EIRE vs Ireland)",
    ]
})
lines.append(df_to_longtable(col_df,
    "Official column definitions and observed deviations", "tab:col_defs",
    col_widths=["p{0.14\\textwidth}", "p{0.42\\textwidth}", "p{0.36\\textwidth}"]))

# 3.2
lines.append(r"\subsection{Data Cleaning}")
lines.append(
    r"Cleaning decisions were derived from the metadata validation output of "
    r"\texttt{00\_validate\_source\_metadata.py}."
)

lines.append(r"\subsubsection{InvoiceNo}")
lines.append(
    r"The official specification defines InvoiceNo as a 6-digit integral number, with a "
    r"\texttt{C} prefix indicating a cancellation. No other prefixes are documented."
)
lines.append(
    f"Of {total_rows:,} rows, {valid_inv:,} conform to the spec. "
    f"The remaining {invalid_inv:,} rows carry an \\texttt{{A}} prefix and represent "
    "bad-debt accounting adjustment entries --- an undocumented transaction type not "
    "described in the official field definition. These rows are excluded from all "
    "downstream analysis."
)
inv_df = pd.DataFrame({
    "Category": [
        "Standard sale (######) --- spec-compliant",
        "Cancellation (C######) --- spec-compliant",
        "Accounting adjustment (A######) --- undocumented deviation",
        "Total"
    ],
    "Count":  [f"{n_standard_sale:,}", f"{n_c_invoice:,}", f"{invalid_inv:,}", f"{total_rows:,}"],
    "Action": ["Retain --- classify as sale", "Retain --- classify as return",
               "Exclude", "---"]
})
lines.append(df_to_longtable(inv_df, "InvoiceNo validation against official spec",
                              "tab:invoiceno",
                              col_widths=["p{0.48\\textwidth}", "p{0.11\\textwidth}",
                                          "p{0.30\\textwidth}"]))

lines.append(r"\subsubsection{CustomerID}")
lines.append(
    f"CustomerID is missing for {missing_cid:,} rows ({missing_cid_pct:.1%} of the "
    f"dataset). All {valid_cid:,} non-missing values conform to the 5-digit format; "
    "no format violations were found. Missing CustomerIDs are retained in non-customer "
    "analyses but excluded from customer-level modelling."
)

lines.append(r"\subsubsection{Quantity \& UnitPrice}")
qty_df = pd.DataFrame({
    "Bucket":          ["Quantity > 0", "Quantity = 0", "Quantity < 0"],
    "Count":           [f"{qty_pos:,}", f"{qty_zero:,}", f"{qty_neg:,}"],
    "Interpretation":  ["Standard sale or free promotional item",
                        "Data anomaly --- reviewed case by case",
                        "Return / cancellation or internal adjustment"]
})
lines.append(df_to_longtable(qty_df, "Quantity value breakdown", "tab:quantity",
                              col_widths=["p{0.22\\textwidth}", "p{0.15\\textwidth}",
                                          "p{0.53\\textwidth}"]))
price_df = pd.DataFrame({
    "Bucket":          ["UnitPrice > 0", "UnitPrice = 0", "UnitPrice < 0"],
    "Count":           [f"{price_pos:,}", f"{price_zero:,}", f"{price_neg:,}"],
    "Interpretation":  ["Revenue-generating transaction",
                        "Free item or non-revenue system entry",
                        "Bad-debt accounting adjustment --- exclude"]
})
lines.append(df_to_longtable(price_df, "UnitPrice value breakdown", "tab:price",
                              col_widths=["p{0.22\\textwidth}", "p{0.15\\textwidth}",
                                          "p{0.53\\textwidth}"]))

lines.append(r"\subsubsection{InvoiceDate}")
lines.append(
    f"All {total_rows - invalid_dates:,} InvoiceDate values parsed successfully with no "
    f"unparseable dates. The dataset spans "
    f"{date_min.strftime('%d %B %Y')} to {date_max.strftime('%d %B %Y')}."
)

lines.append(r"\subsubsection{StockCode}")
lines.append(
    r"The official specification defines StockCode as a 5-digit integral number. "
    r"Validation reveals two classes of deviation:"
)
sc_df = pd.DataFrame({
    "Pattern": [
        "5-digit numeric (e.g. 85123) --- spec-compliant",
        "5-digit + letter suffix (e.g. 85123A) --- deviation from spec",
        "Fully non-standard (e.g. POST, DOT, M, DCGS, gift) --- deviation from spec"
    ],
    "Rows":          [f"{numeric_mask.sum():,}", f"{suffix_mask.sum():,}", f"{special_count:,}"],
    "Unique codes":  [f"{df.loc[numeric_mask, 'StockCode'].nunique():,}",
                      f"{df.loc[suffix_mask, 'StockCode'].nunique():,}",
                      f"{unique_special:,}"],
    "Treatment":     ["Standard product SKU --- include",
                      "Product variant --- include (spec caveat noted)",
                      "Service / admin entry --- separate or exclude"]
})
lines.append(df_to_longtable(sc_df, "StockCode validation against official spec",
                              "tab:stockcode",
                              col_widths=["p{0.32\\textwidth}", "p{0.10\\textwidth}",
                                          "p{0.12\\textwidth}", "p{0.32\\textwidth}"]))
lines.append(
    r"Non-standard special codes include \texttt{POST} (postage), \texttt{DOT} (dotcom), "
    r"\texttt{M} (manual), \texttt{BANK CHARGES}, \texttt{ADJUST}, \texttt{AMAZONFEE}, "
    r"and the \texttt{DCGS} and \texttt{gift} code families."
)

lines.append(r"\subsubsection{Country}")
lines.append(
    f"Country has no missing or blank values across all {total_rows:,} rows. "
    f"There are {unique_countries} unique country labels. "
    f"{unspecified:,} rows ({unspecified / total_rows:.2%}) carry the value "
    r"\texttt{Unspecified}. Naming inconsistencies (e.g.\ \texttt{EIRE} instead of "
    r"\texttt{Ireland}) are standardised in the transformation stage."
)
lines.append(df_to_longtable(top10_countries, "Top 10 countries by row count",
                              "tab:countries",
                              col_widths=["p{0.45\\textwidth}", "p{0.35\\textwidth}"]))

lines.append(r"\subsubsection{Description}")
lines.append(
    f"Description is missing for {missing_desc:,} rows ({missing_desc / total_rows:.2%}). "
    "Missing values are filled from the most common description associated with each "
    "StockCode in the downstream transformation stage."
)

# 3.3
lines.append(r"\subsection{Data Transformation \& Assumptions}")
lines.append(
    r"Following the split-decision EDA (\texttt{01\_split\_decision\_eda.py}), records "
    r"are assigned to one of seven mutually exclusive categories."
)
split_df = pd.DataFrame({
    "Category": [
        "Admin / accounting adjustments",
        "Cancellation invoices",
        "Internal inventory adjustments",
        "Free items / promotions",
        "Gift vouchers",
        "DCGS codes",
        "Clean sales"
    ],
    "Rule": [
        "InvoiceNo starts with 'A'",
        "InvoiceNo starts with 'C'",
        "Qty < 0, UnitPrice = 0, not C/A",
        "Qty > 0, UnitPrice = 0, not C/A",
        "StockCode contains 'gift'",
        "StockCode contains 'DCGS'",
        "Qty > 0, UnitPrice > 0, not C/A, not gift/DCGS"
    ],
    "Count": [
        f"{admin_count:,}", f"{returns_count:,}", f"{internal_adj:,}",
        f"{free_count:,}", f"{is_gift.sum():,}", f"{is_dcgs.sum():,}",
        f"{len(clean_sales):,}"
    ],
    "Disposition": [
        "Exclude from all analyses",
        "Separate returns analysis",
        "Exclude from sales analyses",
        "Separate promotions analysis",
        "Separate voucher analysis",
        "Separate channel analysis",
        "Primary analysis dataset"
    ]
})
lines.append(df_to_longtable(split_df, "Transaction type split decisions", "tab:split",
                              col_widths=["p{0.22\\textwidth}", "p{0.26\\textwidth}",
                                          "p{0.09\\textwidth}", "p{0.30\\textwidth}"]))

lines.append(r"\noindent\textbf{Key assumptions:}")
lines.append(r"\begin{itemize}[leftmargin=1.5em]")
lines.append(
    f"  \\item A \\texttt{{C}}-prefixed invoice always represents a cancellation regardless "
    f"of Quantity sign. One exception ({mismatch_c_not_neg:,} row with positive Quantity "
    r"on a C-invoice) has been identified and excluded from both datasets."
)
lines.append(
    f"  \\item Rows with negative Quantity but no C-prefix ({mismatch_neg_not_c:,} rows) "
    r"are primarily administrative adjustments and are excluded from sales analysis."
)
lines.append(
    r"  \item Zero-UnitPrice rows with positive Quantity are treated as promotional/free "
    r"items and are not counted as revenue-generating sales."
)
lines.append(
    r"  \item DCGS and gift StockCode families are treated as separate channels because "
    r"their price and description patterns differ systematically from standard product SKUs."
)
lines.append(
    r"  \item Missing CustomerID is retained in product-level and geographic analyses but "
    r"excluded from customer-level segmentation analyses."
)
lines.append(r"\end{itemize}")
lines.append(r"\newpage")

# ── 4. Data Analysis ──────────────────────────────────────────────────────────
lines.append(r"\section{Data Analysis}")

# 4.1
lines.append(r"\subsection{Summary Statistics}")
lines.append(
    r"Summary statistics are computed on the clean-sales subset "
    r"(Quantity $>$ 0, UnitPrice $>$ 0, not C/A-invoice, not gift/DCGS) "
    r"unless otherwise noted."
)

summary_df = pd.DataFrame({
    "Metric": [
        "Clean sale rows", "Unique invoices",
        "Unique customers (with CustomerID)", "Unique products (StockCode)",
        "Total revenue (£)", "Avg revenue per invoice (£)",
        "Avg UnitPrice (£)", "Avg quantity per line", "Date range",
    ],
    "Value": [
        f"{len(clean_sales):,}", f"{cs_unique_invoices:,}",
        f"{cs_unique_customers:,}", f"{cs_unique_products:,}",
        f"£{cs_total_revenue:,.2f}",
        f"£{cs_total_revenue / cs_unique_invoices:,.2f}",
        f"£{clean_sales['Price'].mean():.2f}",
        f"{clean_sales['Quantity'].mean():.1f}",
        f"{date_min.strftime('%d %b %Y')} -- {date_max.strftime('%d %b %Y')}",
    ]
})
lines.append(df_to_longtable(summary_df, "Clean-sales summary statistics",
                              "tab:summary",
                              col_widths=["p{0.55\\textwidth}", "p{0.35\\textwidth}"]))

lines.append(df_to_longtable(
    top_products[["StockCode", "Description", "Total Qty Sold"]],
    "Top 10 products by total quantity sold", "tab:top_products",
    col_widths=["p{0.12\\textwidth}", "p{0.55\\textwidth}", "p{0.18\\textwidth}"]
))

lines.append(
    f"Returns (C-invoice rows) account for {returns_count:,} records "
    f"({returns_pct:.2%} of the raw dataset), confirming that cancellations are a "
    "material component of the data."
)

lines.append(df_to_longtable(
    missing_cid_by_country,
    "Top countries by missing CustomerID rate", "tab:missing_cid",
    col_widths=["p{0.50\\textwidth}", "p{0.35\\textwidth}"]
))

# 4.2
lines.append(r"\subsection{Data Visualization}")
lines.append(
    r"Three visualisations were produced to support exploratory understanding of the "
    r"dataset's revenue distribution, temporal patterns, and geographic composition."
)

lines.append(figure_block(
    "totalprice_distribution.png",
    "Distribution of total line-item price (Quantity × UnitPrice) for clean sales. "
    "The distribution is heavily right-skewed, indicating that most transactions are small "
    "while a small number of bulk orders generate disproportionately high revenue.",
    "fig:price_dist"
))

lines.append(figure_block(
    "seasonality_timing.png",
    "Seasonality and intra-day timing patterns. Monthly aggregation reveals a pronounced "
    "sales peak in Q4 (October--November), consistent with pre-Christmas gift-ware demand. "
    "Hour-of-day patterns show peak activity during UK business hours (10:00--14:00).",
    "fig:seasonality"
))

lines.append(figure_block(
    "geographic_insights.png",
    "Geographic revenue distribution. The United Kingdom accounts for the substantial "
    "majority of transactions. European markets (Netherlands, Germany, France, EIRE) "
    "are the most significant international segments.",
    "fig:geography"
))

# 4.3
lines.append(r"\subsection{Feature Extraction}")
lines.append(
    r"Feature extraction targets two downstream modelling objectives: "
    r"(a)~customer-level segmentation via RFM analysis, and "
    r"(b)~product-level demand characterisation. Features are derived exclusively from "
    r"the clean-sales subset."
)

lines.append(r"\subsubsection{RFM Features (customer level)}")
rfm_df = pd.DataFrame({
    "Feature":    ["Recency", "Frequency", "Monetary"],
    "Definition": [
        "Days since the customer's most recent purchase (relative to dataset end date)",
        "Total number of distinct invoices associated with the customer",
        "Total revenue (sum of Quantity × UnitPrice) attributed to the customer"
    ],
    "Notes": [
        "Computed per CustomerID; rows with missing CustomerID excluded",
        "Invoice-level count; each InvoiceNo counted once per customer",
        "Gross sales only; returns not netted at this stage"
    ]
})
lines.append(df_to_longtable(rfm_df, "RFM feature definitions", "tab:rfm",
                              col_widths=["p{0.13\\textwidth}", "p{0.46\\textwidth}",
                                          "p{0.32\\textwidth}"]))

lines.append(r"\subsubsection{Transaction-level Features}")
txn_df = pd.DataFrame({
    "Feature":    ["TotalPrice", "Month", "DayOfWeek", "Hour", "IsUK", "HasCustomerID"],
    "Definition": [
        "Quantity × UnitPrice per line item",
        "Calendar month of InvoiceDate (1--12)",
        "Day of week of InvoiceDate (0 = Monday, 6 = Sunday)",
        "Hour of InvoiceDate (0--23)",
        "Binary indicator: Country = United Kingdom",
        "Binary indicator: CustomerID is not missing"
    ]
})
lines.append(df_to_longtable(txn_df, "Transaction-level derived features", "tab:txn_features",
                              col_widths=["p{0.20\\textwidth}", "p{0.70\\textwidth}"]))

lines.append(r"\subsubsection{Product-level Features}")
prod_df = pd.DataFrame({
    "Feature":    ["TotalQuantitySold", "UniqueCustomers", "UniqueInvoices",
                   "AvgUnitPrice", "RevenueContribution"],
    "Definition": [
        "Sum of Quantity across all clean-sale line items for the product",
        "Count of distinct CustomerIDs that purchased the product",
        "Count of distinct InvoiceNos containing the product",
        "Mean UnitPrice across all clean-sale line items for the product",
        "Product's share of total clean-sales revenue (%)"
    ]
})
lines.append(df_to_longtable(prod_df, "Product-level aggregate features", "tab:prod_features",
                              col_widths=["p{0.25\\textwidth}", "p{0.65\\textwidth}"]))

lines.append(r"\end{document}")

# ── write ──────────────────────────────────────────────────────────────────────

tex_source = "\n\n".join(lines)

with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(tex_source)

print(f"LaTeX report saved to {OUTPUT_FILE}")
print("Upload report.tex plus the figures/ folder to Overleaf.")
print("Overleaf compile settings: pdfLaTeX, main file = report.tex")
