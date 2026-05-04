## How to Run

### 1. Prerequisites

Make sure you have the following installed before starting:

- Python 3.9 or later
- R 4.0 or later (with `Rscript` available on your PATH)
- `git`

---

### 2. Clone the repository

```bash
git clone https://github.com/CAWang16/buisness_data_prep.git
cd buisness_data_prep
```

---

### 3. Download the dataset

The raw data is **not tracked in git** and must be downloaded manually.

1. Go to [UCI ML Repository — Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii)
2. Click **Download** and save the file `online_retail_II.xlsx`
3. Place it here inside the project folder:

```
buisness_data_prep/
└── data/
    └── raw/
        └── online_retail_II.xlsx   ← put it here
```

If the `data/raw/` folder does not exist, create it:

```bash
mkdir -p data/raw
```

---

### 4. Set up the virtual environment

```bash
python3 -m venv venv

# macOS / Linux
source venv/bin/activate

# Windows
venv\Scripts\activate
```

Then install dependencies:

```bash
pip install -r requirement.txt
```

---

### 5. Run the pipeline

All scripts must be run **from the project root** (the folder containing `data/`, `scripts/`, `run_all.sh`, etc.).

#### Option A — Run everything at once

```bash
chmod +x run_all.sh
./run_all.sh
```

#### Option B — Run steps manually in order

**Step 0 — Ingest raw data into SQLite**
```bash
python scripts/00_setup_db.py
```
Reads `data/raw/online_retail_II.xlsx`, combines both sheets, and writes `database/retail.db`. Takes ~25–30 seconds.

**Step 1 — Validate raw field metadata**
```bash
python scripts/00_validate_source_metadata.py
python scripts/01_validate_source_metadata.py
```

**Step 2 — Split-decision EDA**
```bash
python scripts/01_split_decision_eda.py
python scripts/02_split_decision_eda.py
```

**Step 3 — Clean the data**
```bash
python scripts/02_clean_data.py
python scripts/03_clean_data.py
```

**Step 4 — Database validation**
```bash
python scripts/04_quick_db_validation.py
python scripts/quick_db_test_validation.py
```

**Step 5 — Customer clustering (R)**
```bash
Rscript scripts/clustering.R
```
Outputs clustering figures to the `figures/` folder.

**Step 6 — Predictive models (R)**
```bash
Rscript scripts/lf_bought_X_buy_Y.R
Rscript scripts/predict_tomorrow_spike.R
```

**Step 7 — Next likely product (Python)**
```bash
python scripts/Next_likely_product.py
```

**Step 8 — Generate reports**
```bash
# Word document
python scripts/generate_report.py

# LaTeX source (for Overleaf)
python scripts/generate_report_tex.py
```

Output files `report.docx` and `report.tex` will appear in the project root.