# "Seasonal products and bulk buying" -> Regressions splines/GAM, Random Forest importance

# Models how product quantity sold changes across months and with price, using 
# a GAM with smoothing splines and a regression spline with cross-validated degrees of freedom. 
# A Random Forest is then trained on UK product-month data to identify which features — month, price, 
# or order frequency — are most important for predicting bulk purchases. 
# The non-UK product-month data serves as the out-of-distribution test set for the Random Forest.

# ── SETUP ─────────────────────────────────────────────────────────────────────
if (!require("RSQLite",    quietly = TRUE)) install.packages("RSQLite")
if (!require("dplyr",      quietly = TRUE)) install.packages("dplyr")
if (!require("lubridate",  quietly = TRUE)) install.packages("lubridate")
if (!require("ggplot2",    quietly = TRUE)) install.packages("ggplot2")
if (!require("stringr",    quietly = TRUE)) install.packages("stringr")
if (!require("arules",     quietly = TRUE)) install.packages("arules")
if (!require("arulesViz",  quietly = TRUE)) install.packages("arulesViz")
if (!require("rstudioapi", quietly = TRUE)) install.packages("rstudioapi")

library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(randomForest)
library(gam)       # GAM / smoothing splines
library(splines)   # bs()
library(boot)      # cv.glm()

# setting correct wd()
if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))
} else {
  script_path <- normalizePath(sub("--file=", "", commandArgs(trailingOnly = FALSE)[
    grep("--file=", commandArgs(trailingOnly = FALSE))
  ]))
  setwd(file.path(dirname(script_path), ".."))
}


# ── STEP 0: establishing db connection ────────────────────────────────────────
db_path <- "database/clean_retail.db"
fig_path <- "figures"

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

# GAM with smoothing splines (same as hw3 ch7 College Outstate question) models
# how quantity sold changes across months and with price.
# Random Forest identifies which features drive bulk purchases.
# Train/test strategy:
#   - 80% of UK product-months -> training
#   - 20% of UK product-months -> in-distribution test
#   - All non-UK product-months -> out-of-distribution test
# Rationale: UK is the dominant market; non-UK serves as an OOD validation set
# to assess international generalisability.

# ── STEP 1: aggregate to product-month level by country ───────────────────────
product_month <- df |>
  group_by(stock_code, description, MonthNum, country) |>
  summarise(
    TotalQty    = sum(quantity),
    Avgprice    = mean(price),
    NumInvoices = n_distinct(invoice_no),
    .groups     = "drop"
  ) |>
  filter(TotalQty > 0) |>
  na.omit()

# ── STEP 2: UK/non-UK split, then 80/20 within UK ─────────────────────────────
uk_pm   <- product_month |> filter(country == "United Kingdom")
nouk_pm <- product_month |> filter(country != "United Kingdom")

set.seed(1)
train_idx  <- sample(1:nrow(uk_pm), 0.8 * nrow(uk_pm))
pm_train   <- uk_pm[train_idx, ]    # UK 80% — train
pm_uk_test <- uk_pm[-train_idx, ]   # UK 20% — in-distribution test
pm_nouk_test <- nouk_pm             # non-UK  — out-of-distribution test

cat("Training rows (UK 80%):            ", nrow(pm_train), "\n")
cat("In-distribution test (UK 20%):     ", nrow(pm_uk_test), "\n")
cat("Out-of-distribution test (non-UK): ", nrow(pm_nouk_test), "\n")

# ── STEP 3: GAM on training data ──────────────────────────────────────────────
# s() applies smoothing spline, same as hw3 gam.fit with s(Expend, 4)
gam_seasonal <- gam(TotalQty ~ s(MonthNum, 4) + s(Avgprice, 4) + s(NumInvoices, 4),
                    data = pm_train)

png(file.path(fig_path, "gam_seasonal.png"), width = 1200, height = 600, res = 150)
par(mfrow = c(1, 3))
plot(gam_seasonal, se = TRUE, col = "blue")
dev.off()

summary(gam_seasonal)  # check "Anova for Nonparametric Effects"

# ── STEP 4: regression spline CV to find best degrees of freedom ───────────────
# Same CV approach as hw3 ch7 nox~dis — uses UK training data only
cv_errors <- rep(NA, 11)
for (i in 3:11) {
  glm_sp <- glm(TotalQty ~ bs(MonthNum, df = i), data = pm_train)
  cv_errors[i] <- cv.glm(pm_train, glm_sp, K = 5)$delta[1]
}
best_df <- which.min(cv_errors)
cat("Best spline df for seasonality:", best_df, "\n")

# ── STEP 5: Random Forest ─────────────────────────────────────────────────────
set.seed(1)
rf_bulk <- randomForest(TotalQty ~ MonthNum + Avgprice + NumInvoices,
                        data       = pm_train,
                        ntree      = 100,   # default is 500, but using 100 to speed up training due to size of data set
                        mtry       = 2,
                        importance = TRUE)



png(file.path(fig_path, "var_importance.png"), width = 1200, height = 600, res = 150)
importance(rf_bulk)
varImpPlot(rf_bulk, main = "Variable Importance for Bulk quantity")
dev.off()

# UK test (in-distribution)
rf_pred_uk <- predict(rf_bulk, pm_uk_test)
cat("\n--- Random Forest: UK Test (in-distribution) ---\n")
cat("Test MSE:", mean((rf_pred_uk - pm_uk_test$TotalQty)^2), "\n")

# non-UK test (out-of-distribution)
rf_pred_nouk <- predict(rf_bulk, pm_nouk_test)
cat("\n--- Random Forest: non-UK Test (out-of-distribution) ---\n")
cat("Test MSE:", mean((rf_pred_nouk - pm_nouk_test$TotalQty)^2), "\n")

