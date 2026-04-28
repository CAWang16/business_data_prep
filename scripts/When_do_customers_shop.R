# "When do customers shop?" -> Logistic regression (predict peak hour/day), LDA

# Investigates when customers are most likely to shop by defining a binary "peak hour" 
# target — the top third of hours by average revenue — and modeling it using hour of day, day of week, and month. 
# Two classifiers are compared: logistic regression and LDA, both trained on UK transactions only. 
# The model is then tested against non-UK data to see if peak-hour patterns hold internationally. 
# A heatmap of average revenue by hour and day is produced as the main visualization.

# ── SETUP ──────────────────────────────────────────────────────────────────────
library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(MASS)      # LDA

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

# METHOD: Logistic Regression + LDA (same style as hw2 mpg01 / Boston crim01)
# We create a binary target: IsPeakHour (1 = top-revenue hours, 0 = off-peak)
# then model it using Hour and DayOfWeek as predictors.

# Step 1: define peak hour (top tercile of avg revenue per hour)
hour_revenue <- df |>
  group_by(Hour) |>
  summarise(AvgRevenue = mean(Revenue))

peak_threshold <- quantile(hour_revenue$AvgRevenue, 0.67)

df_time <- df |>
  left_join(hour_revenue, by = "Hour") |>
  mutate(IsPeakHour = ifelse(AvgRevenue >= peak_threshold, 1, 0))

# Step 2: train/test split — UK = train, non-UK = test (out-of-distribution)
# Rationale: UK is the dominant market (~85% of volume); non-UK serves as a
# held-out out-of-distribution test to assess how well patterns generalise
# internationally (see demand_spike_report.docx for full justification).
train_t <- df_time |> filter(Country == "United Kingdom")
test_t  <- df_time |> filter(Country != "United Kingdom")

# Step 3: Logistic Regression (same as hw2 glm with family = binomial)
glm_time <- glm(IsPeakHour ~ Hour + DayOfWeek + MonthNum,
                data = train_t, family = binomial)
summary(glm_time)

glm_probs <- predict(glm_time, test_t, type = "response")
glm_class <- ifelse(glm_probs > 0.5, 1, 0)
table(glm_class, test_t$IsPeakHour)          # confusion matrix
mean(glm_class != test_t$IsPeakHour)         # test error rate

# Step 4: LDA (same as hw2 lda on mpg01)
lda_time  <- lda(IsPeakHour ~ Hour + DayOfWeek + MonthNum, data = train_t)
lda_pred  <- predict(lda_time, test_t)
table(lda_pred$class, test_t$IsPeakHour)     # confusion matrix
mean(lda_pred$class != test_t$IsPeakHour)    # test error rate

# Step 5: visualize — average revenue by hour and day
df |>
  group_by(Hour, DayOfWeek) |>
  summarise(AvgRevenue = mean(Revenue), .groups = "drop") |>
  ggplot(aes(x = Hour, y = factor(DayOfWeek), fill = AvgRevenue)) +
  geom_tile() +
  scale_fill_viridis_c() +
  scale_y_discrete(labels = c("Mon","Tue","Wed","Thu","Fri","Sat","Sun")) +
  labs(title = "Q3: Average Revenue by Hour and Day of Week",
       x = "Hour of Day", y = NULL, fill = "Avg Revenue (£)") +
  theme_minimal()
