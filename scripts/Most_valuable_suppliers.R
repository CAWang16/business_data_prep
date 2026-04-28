# "Most valuable suppliers" -> Linear regression, Lasso/Ridge for feature selection

# ── SETUP ──────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(glmnet)    # Lasso/Ridge

db_path <- "database/retail.db"
con <- dbConnect(RSQLite::SQLite(), db_path)

df <- dbReadTable(con, "online_retail_clean") |>
  mutate(
    InvoiceDate = as.POSIXct(InvoiceDate, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    Month       = floor_date(InvoiceDate, "month"),
    MonthNum    = month(InvoiceDate),
    MonthLbl    = month(InvoiceDate, label = TRUE, abbr = TRUE),
    DayOfWeek   = wday(InvoiceDate, week_start = 1),
    Hour        = hour(InvoiceDate),
    Quarter     = quarter(InvoiceDate)
  )

# call dbDisconnect(con) when finished working with a connection 

# METHOD: Lasso regression (same as hw3 glmnet alpha=1) to find which RFM
# dimensions best predict total customer value. Ridge for comparison.

# Step 1: build supplier-level RFM (treating StockCode as "supplier proxy")
snapshot <- max(df$InvoiceDate)

rfm_supplier <- df |>
  group_by(StockCode, Description) |>
  summarise(
    Recency   = as.numeric(difftime(snapshot, max(InvoiceDate), units = "days")),
    Frequency = n_distinct(Invoice),
    Monetary  = sum(Revenue),
    AvgPrice  = mean(Price),
    TotalQty  = sum(Quantity),
    .groups   = "drop"
  ) |>
  filter(Frequency >= 5) |>    # remove one-off products
  na.omit()

# Step 2: model Monetary (total revenue) from Recency, Frequency, AvgPrice, TotalQty
# using Lasso — same approach as hw3 ch6 college Apps question

# Train/test split — UK = train, non-UK = test (out-of-distribution)
# Rationale: UK is the dominant market (~85% of volume); non-UK serves as a
# held-out out-of-distribution test to assess how well patterns generalise
# internationally (see demand_spike_report.docx for full justification).
rfm_supplier_country <- df |>
  group_by(StockCode, Description, Country) |>
  summarise(
    Recency   = as.numeric(difftime(snapshot, max(InvoiceDate), units = "days")),
    Frequency = n_distinct(Invoice),
    Monetary  = sum(Revenue),
    AvgPrice  = mean(Price),
    TotalQty  = sum(Quantity),
    .groups   = "drop"
  ) |>
  filter(Frequency >= 5) |>
  na.omit()

rfm_train <- rfm_supplier_country |> filter(Country == "United Kingdom") |> select(-StockCode, -Description, -Country)
rfm_test  <- rfm_supplier_country |> filter(Country != "United Kingdom") |> select(-StockCode, -Description, -Country)

x_train <- model.matrix(Monetary ~ Recency + Frequency + AvgPrice + TotalQty, data = rfm_train)[, -1]
y_train <- rfm_train$Monetary
x_test  <- model.matrix(Monetary ~ Recency + Frequency + AvgPrice + TotalQty, data = rfm_test)[, -1]
y_test  <- rfm_test$Monetary

# Lasso (alpha = 1)
set.seed(1)
cv_lasso_sup <- cv.glmnet(x_train, y_train, alpha = 1)
plot(cv_lasso_sup)
title("'Most Valuable Supplier': Lasso CV — Supplier Value", line = 3)

lasso_pred_sup <- predict(cv_lasso_sup, s = cv_lasso_sup$lambda.min, newx = x_test)
cat("Lasso test MSE (non-UK):", mean((lasso_pred_sup - y_test)^2), "\n")
predict(cv_lasso_sup, type = "coefficients", s = cv_lasso_sup$lambda.min)

# Ridge (alpha = 0) for comparison
cv_ridge_sup <- cv.glmnet(x_train, y_train, alpha = 0)
ridge_pred_sup <- predict(cv_ridge_sup, s = cv_ridge_sup$lambda.min, newx = x_test)
cat("Ridge test MSE (non-UK):", mean((ridge_pred_sup - y_test)^2), "\n")

# Step 3: visualize top 20 suppliers by Monetary value
rfm_supplier |>
  slice_max(Monetary, n = 20) |>
  ggplot(aes(x = reorder(str_trunc(Description, 30), Monetary), y = Monetary)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "'Most Valuable Supplier': Top 20 Most Valuable Products (Supplier Proxy)",
       x = NULL, y = "Total Revenue (£)") +
  theme_minimal()
