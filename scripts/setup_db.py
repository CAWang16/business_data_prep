import pandas as pd
import sqlite3
import os
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
raw_file_path = os.path.join(BASE_DIR, "data", "processed")
db_path = os.path.join(BASE_DIR, "database")

# i move the data_cleaning.py outputs to ../data/processed/
csv_file = os.path.join(raw_file_path, "online_retail_II_cleaned.csv") # anders's cleaned file
db_file = os.path.join(db_path, "retail.db")
table_name = "online_retail"

if not os.path.exists(csv_file):
    print(f"Error: {csv_file} not found. Please check the file is in the folder")
    exit(1)

os.makedirs(db_path, exist_ok=True)

print(f"Reading {csv_file}...")
start = time.time()
df = pd.read_csv(csv_file, low_memory=False)  # suppresses the DtypeWarning
elapsed = time.time() - start
print(f"Done. {len(df)} rows, {len(df.columns)} columns loaded in {elapsed:.1f}s")

print(f"Writing to {db_file}...")
start = time.time()
conn = sqlite3.connect(db_file)
df.to_sql(table_name, conn, if_exists="replace", index=False)
conn.close()
final_elapsed = time.time() - start

print(f"Finished. Written in {final_elapsed:.1f}s")
print(f"Data saved to {db_file}")
print(f"\nTo use in R:")
print(f"library(RSQLite)")
print(f"con <- dbConnect(RSQLite::SQLite(), '{db_file}')")
print(f"df <- dbReadTable(con, '{table_name}')")
