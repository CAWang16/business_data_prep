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

# change wd to where ever the retail.db file lives
# on my machine, it lives in business_data_prep
setwd("../../")

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

# call dbDisconnect(con) when finished working with a connection 

# METHOD: GAM with smoothing splines (same as hw3 ch7 College Outstate question)
# Models how Quantity sold changes smoothly across months, and whether
# higher prices predict bulk purchases.

# Step 1: aggregate to product-month level
product_month <- df |>
  group_by(StockCode, Description, MonthNum) |>
  summarise(
    TotalQty    = sum(Quantity),
    AvgPrice    = mean(Price),
    NumInvoices = n_distinct(Invoice),
    .groups     = "drop"
  ) |>
  filter(TotalQty > 0) |>
  na.omit()

# Step 2: GAM — smooth effect of Month and Price on Quantity sold
# s() applies smoothing spline, same as hw3 gam.fit with s(Expend, 4)
gam_seasonal <- gam(TotalQty ~ s(MonthNum, 4) + s(AvgPrice, 4) + s(NumInvoices, 4),
                    data = product_month)

par(mfrow = c(1, 3))
plot(gam_seasonal, se = TRUE, col = "blue")  # same plot style as hw3

summary(gam_seasonal)  # check "Anova for Nonparametric Effects" for nonlinear vars

# Step 3: regression spline on Month alone — compare df via CV (same as hw3 ch7 nox~dis)
library(boot)
cv_errors_season <- rep(NA, 11)

for (i in 3:11) {
  glm_sp <- glm(TotalQty ~ bs(MonthNum, df = i), data = product_month)
  cv_errors_season[i] <- cv.glm(product_month, glm_sp)$delta[1]
}

best_df_season <- which.min(cv_errors_season)
cat("Best spline df for seasonality:", best_df_season, "\n")

# Step 4: Random Forest — which product features predict bulk buying?
# (same structure as hw4 randomForest on Carseats/Boston)
set.seed(1)
train_pm <- sample(1:nrow(product_month), 0.8 * nrow(product_month))

rf_bulk <- randomForest(TotalQty ~ MonthNum + AvgPrice + NumInvoices,
                        data    = product_month,
                        subset  = train_pm,
                        mtry    = 2,
                        importance = TRUE)

importance(rf_bulk)
varImpPlot(rf_bulk, main = "Q5: Variable Importance for Bulk Quantity")

rf_pred <- predict(rf_bulk, product_month[-train_pm, ])
cat("Random Forest test MSE:", 
    mean((rf_pred - product_month$TotalQty[-train_pm])^2), "\n")

