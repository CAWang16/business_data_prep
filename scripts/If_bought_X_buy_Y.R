# If bought X, buy Y -> Boosting (gbm), Random Forest, Association Rules

# Builds a binary co-purchase model for the most frequently bought product, 
# predicting whether a given invoice contains that item using basket-level features 
# like number of items, average price, total quantity, and time variables. 
# A GBM (boosting) and a Random Forest are both trained on UK invoices and tested on non-UK invoices, 
# with variable importance plots identifying which basket features most strongly predict co-purchase behavior.

# ── SETUP ─────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(randomForest)
library(gbm)       # Boosting
library(splines)   # bs()

# seting correct wd
setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))


# ── STEP 0: establishing db connection ────────────────────────────────────────
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

dbDisconnect(con) # finished working with a connection 

# Boosting (gbm, same as hw4 ch8 Hitters/Caravan) predicts whether a given
# invoice contains the most-bought product, using basket-level features.
# Random Forest used for comparison and variable importance.
# Train/test strategy:
#   - 80% of UK invoices -> training
#   - 20% of UK invoices -> in-distribution test
#   - All non-UK invoices -> out-of-distribution test
# Rationale: UK is the dominant market; non-UK serves as an OOD validation set
# to assess international generalisability.

# ── STEP 1: build invoice-level feature matrix (retain Country for splitting) ──
invoice_features <- df |>
  mutate(Category = word(Description, 1)) |>
  group_by(InvoiceNo, Country) |>
  summarise(
    NumItems      = n(),
    TotalRevenue  = sum(Revenue),
    AvgPrice      = mean(Price),
    TotalQty      = sum(Quantity),
    NumCategories = n_distinct(Category),
    MonthNum      = first(MonthNum),
    DayOfWeek     = first(DayOfWeek),
    Hour          = first(Hour),
    .groups       = "drop"
  )

# ── STEP 2: define target product (most bought item, from UK training invoices) ─
uk_invoices <- invoice_features |> filter(Country == "United Kingdom")

set.seed(1)
train_inv_idx <- sample(1:nrow(uk_invoices), 0.8 * nrow(uk_invoices))
uk_train_inv  <- uk_invoices[train_inv_idx, ]
uk_test_inv   <- uk_invoices[-train_inv_idx, ]
nouk_inv      <- invoice_features |> filter(Country != "United Kingdom")

# Identify top product from UK training invoices only (avoids leakage)
top_product <- df |>
  filter(InvoiceNo %in% uk_train_inv$InvoiceNo) |>
  count(Description, sort = TRUE) |>
  slice(1) |>
  pull(Description)

cat("Modeling purchase likelihood for:", top_product, "\n")

# ── STEP 3: label invoices that contain the target product ────────────────────
target_invoices <- df |>
  filter(Description == top_product) |>
  distinct(InvoiceNo) |>
  mutate(BoughtTarget = 1)

add_target <- function(inv_df) {
  inv_df |>
    left_join(target_invoices, by = "InvoiceNo") |>
    mutate(BoughtTarget = ifelse(is.na(BoughtTarget), 0, 1)) |>
    select(-InvoiceNo, -Country) |>
    na.omit()
}

train_boost   <- add_target(uk_train_inv)   # UK 80%
test_uk_boost <- add_target(uk_test_inv)    # UK 20%
test_nouk_boost <- add_target(nouk_inv)     # non-UK

cat("Training rows (UK 80%):            ", nrow(train_boost), "\n")
cat("In-distribution test (UK 20%):     ", nrow(test_uk_boost), "\n")
cat("Out-of-distribution test (non-UK): ", nrow(test_nouk_boost), "\n")

# ── STEP 4: Boosting ──────────────────────────────────────────────────────────
# same gbm setup as hw4 Caravan (distribution = "bernoulli")
boost_basket <- gbm(BoughtTarget ~ .,
                    data              = train_boost,
                    distribution      = "bernoulli",
                    n.trees           = 1000,
                    shrinkage         = 0.01,
                    interaction.depth = 2)

summary(boost_basket)  # variable importance — same as hw4

# UK test (in-distribution)
boost_probs_uk <- predict(boost_basket, test_uk_boost, n.trees = 1000, type = "response")
boost_pred_uk  <- ifelse(boost_probs_uk > 0.2, 1, 0)
cat("\n--- Boosting: UK Test (in-distribution) ---\n")
print(table(Predicted = boost_pred_uk, Actual = test_uk_boost$BoughtTarget))
cat("Test error rate:", mean(boost_pred_uk != test_uk_boost$BoughtTarget), "\n")

# non-UK test (out-of-distribution)
boost_probs_nouk <- predict(boost_basket, test_nouk_boost, n.trees = 1000, type = "response")
boost_pred_nouk  <- ifelse(boost_probs_nouk > 0.2, 1, 0)
cat("\n--- Boosting: non-UK Test (out-of-distribution) ---\n")
print(table(Predicted = boost_pred_nouk, Actual = test_nouk_boost$BoughtTarget))
cat("Test error rate:", mean(boost_pred_nouk != test_nouk_boost$BoughtTarget), "\n")

# ── STEP 5: Random Forest ─────────────────────────────────────────────────────
# same structure as hw4 rf.carseats
set.seed(1)
rf_basket <- randomForest(as.factor(BoughtTarget) ~ .,
                          data       = train_boost,
                          mtry       = 3,
                          importance = TRUE)

# UK test (in-distribution)
rf_pred_uk <- predict(rf_basket, test_uk_boost)
cat("\n--- Random Forest: UK Test (in-distribution) ---\n")
print(table(Predicted = rf_pred_uk, Actual = test_uk_boost$BoughtTarget))
cat("Test error rate:", mean(rf_pred_uk != test_uk_boost$BoughtTarget), "\n")

# non-UK test (out-of-distribution)
rf_pred_nouk <- predict(rf_basket, test_nouk_boost)
cat("\n--- Random Forest: non-UK Test (out-of-distribution) ---\n")
print(table(Predicted = rf_pred_nouk, Actual = test_nouk_boost$BoughtTarget))
cat("Test error rate:", mean(rf_pred_nouk != test_nouk_boost$BoughtTarget), "\n")

varImpPlot(rf_basket, main = "What Predicts Co-Purchase?")
