#!/bin/bash
set -e

echo "Starting full project pipeline..."

pip3 install -r requirement.txt
python scripts/00_setup_db.py
python scripts/01_validate_source_metadata.py
python scripts/02_validate_source_metadata.py
python scripts/03_split_decision_eda.py
python scripts/04_clean_data.py
python scripts/05_split_decision_eda.py
python scripts/06_quick_db_validation.py

export R_PROFILE_USER=$HOME/.Rprofile
echo 'options(repos = c(CRAN = "https://cloud.r-project.org/"))' > $HOME/.Rprofile

echo "Installing R dependencies..."
Rscript -e 'install.packages(c("lubridate", "dplyr", "ggplot2", "arules", "arulesViz"), dependencies=TRUE)'

Rscript scripts/07_clustering.R
Rscript scripts/08_If_bought_X_buy_Y.R
python scripts/09_Next_likely_product.py
Rscript scripts/10_predict_tomorrow_spike.R
python scripts/11_quick_db_test_validation.py
Rscript scripts/12_Seasonal_products_and_bulk_buying.R
Rscript scripts/13_When_do_customers_shop.R

python scripts/14_generate_report.py
python scripts/15_generate_report_tex.py

echo "Full project pipeline finished successfully."
