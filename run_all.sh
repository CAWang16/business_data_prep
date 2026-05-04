#!/bin/bash
set -e

echo "Starting full project pipeline..."

python scripts/00_setup_db.py
python scripts/00_validate_source_metadata.py
python scripts/01_validate_source_metadata.py
python scripts/01_split_decision_eda.py
python scripts/02_clean_data.py
python scripts/02_split_decision_eda.py
python scripts/03_clean_data.py
python scripts/04_quick_db_validation.py


Rscript scripts/clustering.R
Rscript scripts/If_bought_X_buy_Y.R
Rscript scripts/Next_likely_product.py
Rscript scripts/predict_tomorrow_spike.R
Rscript scripts/quick_db_test_validation.py
Rscript scripts/Seasonal_products_and_bulk_buying.R
Rscript scripts/When_do_customers_shop.R

python scripts/generate_report.py
python scripts/generate_report_tex.py

echo "Full project pipeline finished successfully."
