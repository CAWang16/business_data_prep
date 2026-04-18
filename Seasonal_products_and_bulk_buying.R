# "Seasonal products and bulk buying" -> Regressions splines/GAM, Random Forest importance


# ── SETUP ──────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(randomForest)
library(gam)       # GAM / smoothing splines
library(splines)   # bs()

con <- dbConnect(RSQLite::SQLite(), "retail.db")

df <- dbReadTable(con, "online_retail") |>
  mutate(
    InvoiceDate = as.POSIXct(InvoiceDate, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    Month       = floor_date(InvoiceDate, "month"),
    MonthNum    = month(InvoiceDate),          # numeric 1-12 (needed for models)
    MonthLbl    = month(InvoiceDate, label = TRUE, abbr = TRUE),
    DayOfWeek   = wday(InvoiceDate, week_start = 1), # 1=Mon ... 7=Sun
    Hour        = hour(InvoiceDate),
    Quarter     = quarter(InvoiceDate),
    IsCancelled = grepl("^C", as.character(Invoice))
  ) |>
  rename(Revenue = TotalPrice) |>
  filter(!IsCancelled, Quantity > 0, Price > 0)

setwd("C:/Users/taylo/OneDrive/Desktop/CSP571/Project")