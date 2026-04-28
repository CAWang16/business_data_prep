# If bought X, buy Y -> Boosting (gbm), Random Forest, Association Rules

# ── SETUP ──────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(randomForest)
library(gbm)       # Boosting
library(splines)   # bs()

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

# METHOD: Boosting (gbm, same as hw4 ch8 Hitters/Caravan questions)
# For each product, boost a binary outcome: "was this item bought in the
# same basket?" using other product-level features as predictors.
# Also uses Random Forest feature importance for a complementary view.

# Step 1: build invoice-level feature matrix
# For each invoice, create indicators for product categories
invoice_features <- df |>
  mutate(Category = word(Description, 1)) |>
  group_by(Invoice) |>
  summarise(
    NumItems     = n(),
    TotalRevenue = sum(Revenue),
    AvgPrice     = mean(Price),
    TotalQty     = sum(Quantity),
    NumCategories = n_distinct(Category),
    MonthNum     = first(MonthNum),
    DayOfWeek    = first(DayOfWeek),
    Hour         = first(Hour),
    .groups      = "drop"
  )

# Step 2: pick a target product to model (most commonly bought item)
top_product <- df |>
  count(Description, sort = TRUE) |>
  slice(1) |>
  pull(Description)

cat("Modeling purchase likelihood for:", top_product, "\n")

# invoices that contain the target product
target_invoices <- df |>
  filter(Description == top_product) |>
  distinct(Invoice) |>
  mutate(BoughtTarget = 1)

model_df <- invoice_features |>
  left_join(target_invoices, by = "Invoice") |>
  mutate(BoughtTarget = ifelse(is.na(BoughtTarget), 0, 1)) |>
  select(-Invoice) |>
  na.omit()

# Step 3: train/test split — UK = train, non-UK = test (out-of-distribution)
# Rationale: UK is the dominant market (~85% of volume); non-UK serves as a
# held-out out-of-distribution test to assess how well patterns generalise
# internationally (see demand_spike_report.docx for full justification).
# Join country back onto model_df before splitting
model_df_country <- invoice_features |>
  left_join(target_invoices, by = "Invoice") |>
  mutate(BoughtTarget = ifelse(is.na(BoughtTarget), 0, 1)) |>
  left_join(df |> distinct(Invoice, Country), by = "Invoice") |>
  na.omit()

train_boost <- model_df_country |> filter(Country == "United Kingdom") |> select(-Invoice, -Country)
test_boost  <- model_df_country |> filter(Country != "United Kingdom") |> select(-Invoice, -Country)

# Step 4: Boosting — same gbm setup as hw4 Caravan (distribution="bernoulli")
boost_basket <- gbm(BoughtTarget ~ .,
                    data         = train_boost,
                    distribution = "bernoulli",
                    n.trees      = 1000,
                    shrinkage    = 0.01,
                    interaction.depth = 2)

summary(boost_basket)  # variable importance plot — same as hw4

# predict (same threshold logic as hw4 Caravan > 0.2)
boost_probs <- predict(boost_basket, test_boost, n.trees = 1000, type = "response")
boost_pred  <- ifelse(boost_probs > 0.2, 1, 0)
table(boost_pred, test_boost$BoughtTarget)          # confusion matrix
mean(boost_pred != test_boost$BoughtTarget)         # test error rate

# Step 5: Random Forest for comparison + importance (same as hw4 rf.carseats)
set.seed(1)
rf_basket <- randomForest(as.factor(BoughtTarget) ~ .,
                          data       = train_boost,
                          mtry       = 3,
                          importance = TRUE)

rf_pred_basket <- predict(rf_basket, test_boost)
table(rf_pred_basket, test_boost$BoughtTarget)
mean(rf_pred_basket != test_boost$BoughtTarget)

varImpPlot(rf_basket, main = "Q6: What Predicts Co-Purchase?")