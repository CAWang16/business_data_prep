# "Most valuable suppliers" -> Linear regression, Lasso/Ridge for feature selection

# Treats each product (stock_code) as a "supplier proxy" and builds an RFM profile — 
# recency, frequency, monetary value, average price, and total quantity — at the product-by-country level. 
# Lasso and Ridge regression are trained on UK products to predict total revenue, with the non-UK product set used as the held-out test. 
# A bar chart of the top 20 highest-revenue products is also generated alongside the Lasso coefficient output.


# ── SETUP ─────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(glmnet)    # Lasso/Ridge

# seting correct wd
setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))


# ── STEP 0: establishing db connection ────────────────────────────────────────
db_path <- "database/clean_retail.db"
con <- dbConnect(RSQLite::SQLite(), db_path)

df <- dbReadTable(con, "clean_product_sales") |>
  mutate(
    invoice_date = as.POSIXct(invoice_date, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    Revenue      = quantity * price,
    MonthNum     = month(invoice_date),
    DayOfWeek    = wday(invoice_date, week_start = 1),
    Hour         = hour(invoice_date),
    Quarter      = quarter(invoice_date)
  )

dbDisconnect(con) # finished working with a connection 

# Lasso regression (same as hw3 glmnet alpha=1) to find which RFM dimensions
# best predict total product revenue. Ridge used for comparison.
# Train/test strategy:
#   - 80% of UK products -> training
#   - 20% of UK products -> in-distribution test
#   - All non-UK products -> out-of-distribution test
# Rationale: UK is the dominant market; non-UK serves as an OOD validation set
# to assess international generalisability.

# ── STEP 1: build product-level RFM by country ────────────────────────────────
snapshot <- max(df$invoice_date)

rfm_by_country <- df |>
  group_by(stock_code, description, country) |>
  summarise(
    Recency   = as.numeric(difftime(snapshot, max(invoice_date), units = "days")),
    Frequency = n_distinct(invoice_no),
    Monetary  = sum(Revenue),
    Avgprice  = mean(price),
    TotalQty  = sum(quantity),
    .groups   = "drop"
  ) |>
  filter(Frequency >= 5) |>
  na.omit()

# ── STEP 2: UK/non-UK split, then 80/20 within UK ─────────────────────────────
uk_rfm   <- rfm_by_country |> filter(country == "United Kingdom") |> dplyr::select(-stock_code, -description, -country)
nouk_rfm <- rfm_by_country |> filter(country != "United Kingdom") |> dplyr::select(-stock_code, -description, -country)

set.seed(1)
train_idx <- sample(1:nrow(uk_rfm), 0.8 * nrow(uk_rfm))
rfm_train <- uk_rfm[train_idx, ]   # UK 80% — train
rfm_uk_test  <- uk_rfm[-train_idx, ]  # UK 20% — in-distribution test
rfm_nouk_test <- nouk_rfm              # non-UK  — out-of-distribution test

cat("Training rows (UK 80%):            ", nrow(rfm_train), "\n")
cat("In-distribution test (UK 20%):     ", nrow(rfm_uk_test), "\n")
cat("Out-of-distribution test (non-UK): ", nrow(rfm_nouk_test), "\n")

# ── STEP 3: build model matrices ──────────────────────────────────────────────
formula_rfm <- Monetary ~ Recency + Frequency + Avgprice + TotalQty

x_train    <- model.matrix(formula_rfm, data = rfm_train)[, -1]
y_train    <- rfm_train$Monetary

x_uk_test  <- model.matrix(formula_rfm, data = rfm_uk_test)[, -1]
y_uk_test  <- rfm_uk_test$Monetary

x_nouk_test <- model.matrix(formula_rfm, data = rfm_nouk_test)[, -1]
y_nouk_test  <- rfm_nouk_test$Monetary

# ── STEP 4: Lasso (alpha = 1) ─────────────────────────────────────────────────
set.seed(1)
cv_lasso <- cv.glmnet(x_train, y_train, alpha = 1)
plot(cv_lasso)
title("Most Valuable Supplier: Lasso CV", line = 3)

cat("\nLasso coefficients at lambda.min:\n")
print(predict(cv_lasso, type = "coefficients", s = cv_lasso$lambda.min))

# UK test (in-distribution)
lasso_pred_uk <- predict(cv_lasso, s = cv_lasso$lambda.min, newx = x_uk_test)
cat("\n--- Lasso: UK Test (in-distribution) ---\n")
cat("Test MSE:", mean((lasso_pred_uk - y_uk_test)^2), "\n")

# non-UK test (out-of-distribution)
lasso_pred_nouk <- predict(cv_lasso, s = cv_lasso$lambda.min, newx = x_nouk_test)
cat("\n--- Lasso: non-UK Test (out-of-distribution) ---\n")
cat("Test MSE:", mean((lasso_pred_nouk - y_nouk_test)^2), "\n")

# non-uk products have much lower revenue. must scale for fair comparison
# shows true generalization gap in percentage terms, which is much more reportable than raw MSE when the two test sets have different revenue scales.
cat("Lasso UK relative error:    ", 
    sqrt(mean((lasso_pred_uk - y_uk_test)^2)) / mean(y_uk_test), "\n")
cat("Lasso non-UK relative error:", 
    sqrt(mean((lasso_pred_nouk - y_nouk_test)^2)) / mean(y_nouk_test), "\n")

# ── STEP 5: Ridge (alpha = 0) for comparison ──────────────────────────────────
set.seed(1)
cv_ridge <- cv.glmnet(x_train, y_train, alpha = 0)

# UK test (in-distribution)
ridge_pred_uk <- predict(cv_ridge, s = cv_ridge$lambda.min, newx = x_uk_test)
cat("\n--- Ridge: UK Test (in-distribution) ---\n")
cat("Test MSE:", mean((ridge_pred_uk - y_uk_test)^2), "\n")

# non-UK test (out-of-distribution)
ridge_pred_nouk <- predict(cv_ridge, s = cv_ridge$lambda.min, newx = x_nouk_test)
cat("\n--- Ridge: non-UK Test (out-of-distribution) ---\n")
cat("Test MSE:", mean((ridge_pred_nouk - y_nouk_test)^2), "\n")

# non-uk products have much lower revenue. must scale for fair comparison
# shows true generalization gap in percentage terms, which is much more reportable than raw MSE when the two test sets have different revenue scales.
cat("Ridge UK relative error:    ", 
    sqrt(mean((ridge_pred_uk - y_uk_test)^2)) / mean(y_uk_test), "\n")
cat("Ridge non-UK relative error:", 
    sqrt(mean((ridge_pred_nouk - y_nouk_test)^2)) / mean(y_nouk_test), "\n")

# ── STEP 6: Visualize top 20 products by total revenue (UK) ───────────────────
rfm_by_country |>
  filter(country == "United Kingdom") |>
  slice_max(Monetary, n = 20) |>
  ggplot(aes(x = reorder(str_trunc(description, 30), Monetary), y = Monetary)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Most Valuable Supplier: Top 20 Products by Revenue (UK)",
       x = NULL, y = "Total Revenue (GBP)") +
  theme_minimal()

