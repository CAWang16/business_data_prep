import pandas as pd
import sqlite3
import os   
import time



raw_file_path = "data/raw"
db_path = "database/"

excel_file = os.path.join(raw_file_path, "online_retail_II.xlsx")
print(excel_file)
db_file = os.path.join(db_path, "retail.db")
table_name = "online_retail"


if not os.path.exists(excel_file):
    print(f"Error: {excel_file} not found. Please check the file is in the folder")
    exit(1)


print(f"Reading {excel_file} from the dedicated folder.")
print("Note: This file contain more than 1M rows and may take few minutes")


data_file = pd.ExcelFile(excel_file)
sheet_names = data_file.sheet_names
print(f"Found {len(sheet_names)} sheets: {sheet_names}")
sheets = []

for sheet in sheet_names:
    print(f"Loading sheet {sheet}")
    start = time.time()
    df_sheet = data_file.parse(sheet)
    elapsed = time.time() - start
    print(f"Done. {len(df_sheet)} rows loaded in {elapsed}s")
    sheets.append(df_sheet)


print("Combining sheet")
df = pd.concat(sheets, ignore_index=True)
print(f"Total: {len(df)} rows, {len(df.columns)} columns")


print(f"Writing to {db_file}...")
start = time.time()
conn = sqlite3.connect(db_file)
df.to_sql(table_name, conn, if_exists="replace", index=False)
conn.close()
final_elapsed = time.time() - start


print(f"Finished. Written in {final_elapsed}s")
print(f"Data saved to {db_file}")
print(f"To use in R: ")
print(f"library(RSQLite)")
print(f"con <- dbConnect(RSQLite::SQLite(), '{db_file}')")
print(f"df <- dbReadTable(con, '{table_name}')")

