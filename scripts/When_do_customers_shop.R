# "When do customers shop?" -> Logistic regression (predict peak hour/day), LDA

# Investigates when customers are most likely to shop by defining a binary "peak hour" 
# target — the top third of hours by average revenue — and modeling it using hour of day, day of week, and month. 
# Two classifiers are compared: logistic regression and LDA, both trained on UK transactions only. 
# The model is then tested against non-UK data to see if peak-hour patterns hold internationally. 
# A heatmap of average revenue by hour and day is produced as the main visualization.

# ── SETUP ─────────────────────────────────────────────────────────────────────
if (!require("dplyr", quietly = TRUE)) install.packages("dplyr")

library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(MASS)      # LDA

# ── STEP 0: establishing db connection ────────────────────────────────────────
setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))


# establishing db connection
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

# Logistic Regression + LDA (same style as hw2 mpg01 / Boston crim01)
# Binary target: IsPeakHour (1 = top-revenue hours, 0 = off-peak)
# Train/test strategy:
#   - 80% of UK data -> training
#   - 20% of UK data -> in-distribution test
#   - All non-UK data -> out-of-distribution test
# Rationale: UK is the dominant market; non-UK serves as an OOD validation set
# to assess international generalisability.

# ── STEP 1: UK/non-UK split ────────────────────────────────────────────────────
uk_data   <- df |> filter(country == "United Kingdom")
nouk_data <- df |> filter(country != "United Kingdom")

# ── STEP 2: define peak hours from training data only ─────────────────────────
set.seed(1)
train_idx    <- sample(1:nrow(uk_data), 0.8 * nrow(uk_data))
uk_train_raw <- uk_data[train_idx, ]
uk_test_raw  <- uk_data[-train_idx, ]

hour_revenue_train <- uk_train_raw |>
  group_by(Hour) |>
  summarise(AvgRevenue = mean(Revenue), .groups = "drop")

peak_threshold <- quantile(hour_revenue_train$AvgRevenue, 0.67)

# Label rows — use replace_na(0) to handle any hours missing from training
label_peak <- function(data) {
  data |>
    left_join(hour_revenue_train, by = "Hour") |>
    mutate(IsPeakHour = ifelse(!is.na(AvgRevenue) & AvgRevenue >= peak_threshold, 1, 0))
}

uk_train  <- label_peak(uk_train_raw)
uk_test   <- label_peak(uk_test_raw)
nouk_test <- label_peak(nouk_data)


# Aggregate to invoice level before modeling (one row per transaction)
uk_train_inv <- uk_train |>
  group_by(invoice_no) |>
  summarise(
    IsPeakHour = first(IsPeakHour),
    TotalRevenue = sum(Revenue),
    TotalQty = sum(quantity),
    NumItems = n(),
    DayOfWeek = first(DayOfWeek),
    MonthNum = first(MonthNum),
    .groups = "drop"
  )

uk_test_inv <- uk_test |>
  group_by(invoice_no) |>
  summarise(
    IsPeakHour = first(IsPeakHour),
    TotalRevenue = sum(Revenue),
    TotalQty = sum(quantity),
    NumItems = n(),
    DayOfWeek = first(DayOfWeek),
    MonthNum = first(MonthNum),
    .groups = "drop"
  )

nouk_test_inv <- nouk_test |>
  group_by(invoice_no) |>
  summarise(
    IsPeakHour = first(IsPeakHour),
    TotalRevenue = sum(Revenue),
    TotalQty = sum(quantity),
    NumItems = n(),
    DayOfWeek = first(DayOfWeek),
    MonthNum = first(MonthNum),
    .groups = "drop"
  )

# ── STEP 3: reframe — predict IsPeakHour from BASKET features, not Hour ───────
# Hour is the definition of the label so it can't be a predictor.
# Instead use: order value, quantity, number of items, day of week, month.
glm_time <- glm(IsPeakHour ~ TotalRevenue + TotalQty + NumItems + DayOfWeek + MonthNum,
                data = uk_train_inv, family = binomial)
summary(glm_time)

# UK test
glm_probs_uk <- predict(glm_time, uk_test_inv, type = "response")
glm_class_uk <- ifelse(glm_probs_uk > 0.5, 1, 0)
cat("\n--- Logistic Regression: UK Test (in-distribution) ---\n")
print(table(Predicted = glm_class_uk, Actual = uk_test_inv$IsPeakHour))
cat("Test error rate:", mean(glm_class_uk != uk_test_inv$IsPeakHour), "\n")

# non-UK test
glm_probs_nouk <- predict(glm_time, nouk_test_inv, type = "response")
glm_class_nouk <- ifelse(glm_probs_nouk > 0.5, 1, 0)
cat("\n--- Logistic Regression: non-UK Test (out-of-distribution) ---\n")
print(table(Predicted = glm_class_nouk, Actual = nouk_test_inv$IsPeakHour))
cat("Test error rate:", mean(glm_class_nouk != nouk_test_inv$IsPeakHour), "\n")

# ── STEP 4: LDA ───────────────────────────────────────────────────────────────
lda_time <- lda(IsPeakHour ~ TotalRevenue + TotalQty + DayOfWeek + MonthNum,
                data = uk_train_inv)

lda_pred_uk <- predict(lda_time, uk_test_inv)
cat("\n--- LDA: UK Test (in-distribution) ---\n")
print(table(Predicted = lda_pred_uk$class, Actual = uk_test_inv$IsPeakHour))
cat("Test error rate:", mean(lda_pred_uk$class != uk_test_inv$IsPeakHour), "\n")

lda_pred_nouk <- predict(lda_time, nouk_test_inv)
cat("\n--- LDA: non-UK Test (out-of-distribution) ---\n")
print(table(Predicted = lda_pred_nouk$class, Actual = nouk_test_inv$IsPeakHour))
cat("Test error rate:", mean(lda_pred_nouk$class != nouk_test_inv$IsPeakHour), "\n")

# ── STEP 5: Visualize ──────────────────────────────────────────────────────────
png(file.path(fig_path, "avg_rev_by_hour_day.png"), width = 1200, height = 600, res = 150)
df |>
  group_by(Hour, DayOfWeek) |>
  summarise(AvgRevenue = mean(Revenue), .groups = "drop") |>
  ggplot(aes(x = Hour, y = factor(DayOfWeek), fill = AvgRevenue)) +
  geom_tile() +
  scale_fill_viridis_c() +
  scale_y_discrete(labels = c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")) +
  labs(title = "Average Revenue by Hour and Day of Week",
       x = "Hour of Day", y = NULL, fill = "Avg Revenue (GBP)") +
  theme_minimal()
dev.off()

