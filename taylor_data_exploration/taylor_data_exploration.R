# packages
library(RSQLite)
library(dplyr)
library(ggplot2)
library(lubridate)
library(tidyr)
library(stringr)

setwd("../")

con <- dbConnect(RSQLite::SQLite(), 'retail.db')

df_raw <- dbReadTable(con, "online_retail")
colnames(df_raw)
head(df_raw, 3)

df <- dbReadTable(con, "online_retail") |>
 # friendly formatting
   mutate(
    InvoiceDate = as.POSIXct(InvoiceDate, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    Month       = floor_date(InvoiceDate, "month"),
    MonthNum    = month(InvoiceDate, label = TRUE, abbr = TRUE),
    Quarter     = quarter(InvoiceDate),
    IsCancelled = grepl("^C", as.character(Invoice))
  ) |>
  rename(Revenue = TotalPrice) |>
  filter(!IsCancelled, Quantity > 0, Price > 0) # filtering

# call dbDisconnect(con) when finished working with a connection 


# what does the data look like? (basic data quality + overview)
glimpse(df)
summary(df)

cat("Date range:", format(min(df$InvoiceDate)), "to", format(max(df$InvoiceDate)), "\n")
cat("Unique products:", n_distinct(df$StockCode), "\n")
cat("Unique countries:", n_distinct(df$Country), "\n")
cat("Total invoices:", n_distinct(df$Invoice), "\n")


# Q1: How does monthly revenue trend over time?
monthly_revenue <- df |>
  group_by(Month) |>
  summarise(Revenue = sum(Revenue), .groups = "drop")

ggplot(monthly_revenue, aes(x = Month, y = Revenue)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_point(color = "steelblue") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Monthly Revenue Over Time",
       x = "Month", y = "Revenue (£)") +
  theme_minimal()



# Q2: Which countries generate the most revenue?
country_revenue <- df |>
  group_by(Country) |>
  summarise(Revenue = sum(Revenue), Orders = n_distinct(Invoice)) |>
  arrange(desc(Revenue)) |>
  slice_head(n = 10)

ggplot(country_revenue, aes(x = reorder(Country, Revenue), y = Revenue)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Top 10 Countries by Revenue",
       x = NULL, y = "Revenue (£)") +
  theme_minimal()



# Q3: Who are the top customers by revenue? (Customer value distribution)
customer_value <- df |>
  group_by(`Customer.ID`) |>
  summarise(
    TotalRevenue = sum(Revenue),
    NumOrders = n_distinct(Invoice),
    AvgOrderValue = TotalRevenue / NumOrders
  ) |>
  arrange(desc(TotalRevenue))

# Top 10 customers
head(customer_value, 10)

# Distribution of customer spend (log scale shows the spread clearly)
ggplot(customer_value, aes(x = TotalRevenue)) +
  geom_histogram(bins = 50, fill = "steelblue", color = "white") +
  scale_x_log10(labels = scales::comma) +
  labs(title = "Distribution of Customer Lifetime Revenue (log scale)",
       x = "Total Revenue (£, log scale)", y = "Number of Customers") +
  theme_minimal()



# Q4: What are the best-selling products by quantity and revenue?
product_summary <- df |>
  group_by(StockCode, Description) |>
  summarise(
    TotalQty = sum(Quantity),
    TotalRevenue = sum(Revenue),
    .groups = "drop"
  )

# Top 10 by quantity
product_summary |> arrange(desc(TotalQty)) |> slice_head(n = 10) |>
  ggplot(aes(x = reorder(Description, TotalQty), y = TotalQty)) +
  geom_col(fill = "coral") +
  coord_flip() +
  labs(title = "Top 10 Products by Units Sold",
       x = NULL, y = "Total Quantity") +
  theme_minimal()



# Q5: When do customers shop? (Day of week and hour of day patterns)
df <- df |>
  mutate(
    DayOfWeek = wday(InvoiceDate, label = TRUE, abbr = TRUE),
    Hour = hour(InvoiceDate)
  )

# Orders by day of week
df |>
  group_by(DayOfWeek) |>
  summarise(Orders = n_distinct(Invoice)) |>
  ggplot(aes(x = DayOfWeek, y = Orders)) +
  geom_col(fill = "mediumpurple") +
  labs(title = "Number of Orders by Day of Week",
       x = NULL, y = "Number of Orders") +
  theme_minimal()

# Orders by hour of day
df |>
  group_by(Hour) |>
  summarise(Orders = n_distinct(Invoice)) |>
  ggplot(aes(x = Hour, y = Orders)) +
  geom_col(fill = "mediumpurple") +
  labs(title = "Number of Orders by Hour of Day",
       x = "Hour", y = "Number of Orders") +
  theme_minimal()



# Q6: What is the distribution of order values? (Basket size analysis)
basket <- df |>
  group_by(Invoice) |>
  summarise(BasketValue = sum(Revenue), ItemCount = sum(Quantity))

cat("Average basket value: £", round(mean(basket$BasketValue), 2), "\n")
cat("Median basket value: £", round(median(basket$BasketValue), 2), "\n")

ggplot(basket |> filter(BasketValue < quantile(BasketValue, 0.99)), 
       aes(x = BasketValue)) +
  geom_histogram(bins = 60, fill = "steelblue", color = "white") +
  labs(title = "Distribution of Order (Basket) Values",
       subtitle = "Excluding top 1% outliers",
       x = "Order Value (£)", y = "Count") +
  theme_minimal()



# Q7: RFM Segmentation — which customers are most valuable?
# Recency = days since last purchase, Frequency = # orders, Monetary = total spend
snapshot_date <- max(df$InvoiceDate)

rfm <- df |>
  group_by(`Customer.ID`) |>
  summarise(
    Recency   = as.numeric(difftime(snapshot_date, max(InvoiceDate), units = "days")),
    Frequency = n_distinct(Invoice),
    Monetary  = sum(Revenue)
  ) |>
  mutate(
    R_score = ntile(-Recency, 4),   # higher = more recent
    F_score = ntile(Frequency, 4),
    M_score = ntile(Monetary, 4),
    RFM_score = R_score + F_score + M_score
  )

# Plot frequency vs monetary, colored by recency
ggplot(rfm |> filter(Monetary < quantile(Monetary, 0.99)),
       aes(x = Frequency, y = Monetary, color = Recency)) +
  geom_point(alpha = 0.4, size = 1.2) +
  scale_color_viridis_c(direction = -1) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "RFM Customer Segmentation",
       subtitle = "Darker = more recent purchaser",
       x = "Purchase Frequency", y = "Total Spend (£)",
       color = "Days Since\nLast Purchase") +
  theme_minimal()

# Summary of top-scoring customers
rfm |> arrange(desc(RFM_score)) |> head(10)



# Q8: Which months are highest revenue vs. highest order volume?
# (revenue peaks ≠ order peaks — useful for staffing vs. stocking decisions)
monthly_summary <- df |>
  group_by(MonthNum) |>
  summarise(
    Revenue = sum(Revenue),
    Orders  = n_distinct(Invoice),
    AvgOrderValue = Revenue / Orders
  )

# Pivot to long for easy faceting
monthly_summary |>
  pivot_longer(cols = c(Revenue, Orders, AvgOrderValue), names_to = "Metric") |>
  ggplot(aes(x = MonthNum, y = value, group = 1)) +
  geom_col(fill = "steelblue") +
  facet_wrap(~Metric, scales = "free_y") +
  labs(title = "Monthly Revenue, Order Volume, and Avg Order Value",
       x = NULL, y = NULL) +
  theme_minimal()



# Q9: Which products are most seasonal? 
# (products whose sales spike in specific months)
seasonal_products <- df |>
  group_by(Description, MonthNum) |>
  summarise(Quantity = sum(Quantity), .groups = "drop") |>
  group_by(Description) |>
  mutate(
    TotalQty = sum(Quantity),
    MonthShare = Quantity / TotalQty  # what % of annual sales fall in each month
  ) |>
  filter(TotalQty > 500) |>  # only products with meaningful volume
  summarise(SeasonalityScore = max(MonthShare)) |>  # higher = more concentrated in one month
  arrange(desc(SeasonalityScore))

# Top 15 most seasonal products
head(seasonal_products, 15)

# Plot the monthly sales profile of the top 6 most seasonal products
top_seasonal <- head(seasonal_products$Description, 6)

df |>
  filter(Description %in% top_seasonal) |>
  group_by(Description, MonthNum) |>
  summarise(Quantity = sum(Quantity), .groups = "drop") |>
  ggplot(aes(x = MonthNum, y = Quantity, fill = Description)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~Description, scales = "free_y", ncol = 2) +
  labs(title = "Monthly Sales Profile — Most Seasonal Products",
       x = NULL, y = "Units Sold") +
  theme_minimal() +
  theme(strip.text = element_text(size = 7))



# Q10: Which product CATEGORIES sell best by quarter?
# (uses the first word of Description as a rough category proxy)
df |>
  mutate(Category = word(Description, 1)) |>
  group_by(Quarter, Category) |>
  summarise(Revenue = sum(Revenue), .groups = "drop") |>
  group_by(Quarter) |>
  slice_max(Revenue, n = 8) |>
  ggplot(aes(x = reorder(Category, Revenue), y = Revenue, fill = factor(Quarter))) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  facet_wrap(~paste("Q", Quarter), scales = "free") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Top Product Categories by Revenue per Quarter",
       x = NULL, y = "Revenue (£)") +
  theme_minimal() +
  theme(strip.text = element_text(face = "bold"))



# Q11: If a customer bought X, what else did they buy? (basket analysis)
# Finds the most common product PAIRS bought in the same invoice

# Build invoice-product pairs
basket_pairs <- df |>
  select(Invoice, Description) |>
  distinct() |>
  inner_join(
    df |> select(Invoice, Description) |> distinct(),
    by = "Invoice",
    relationship = "many-to-many"
  ) |>
  filter(Description.x < Description.y) |>  # avoid duplicates & self-pairs
  group_by(Description.x, Description.y) |>
  summarise(TimesBoughtTogether = n(), .groups = "drop") |>
  arrange(desc(TimesBoughtTogether))

head(basket_pairs, 20)


# Q12: What is the "lift" of product pairs? 
# Lift > 1 means two products are bought together MORE than chance would predict.
# This is more meaningful than raw co-occurrence counts.

product_freq <- df |>
  select(Invoice, Description) |>
  distinct() |>
  count(Description, name = "ProductCount")

total_invoices <- n_distinct(df$Invoice)

basket_lift <- basket_pairs |>
  left_join(product_freq, by = c("Description.x" = "Description")) |>
  rename(CountX = ProductCount) |>
  left_join(product_freq, by = c("Description.y" = "Description")) |>
  rename(CountY = ProductCount) |>
  mutate(
    SupportX  = CountX / total_invoices,
    SupportY  = CountY / total_invoices,
    SupportXY = TimesBoughtTogether / total_invoices,
    Lift      = SupportXY / (SupportX * SupportY)
  ) |>
  filter(TimesBoughtTogether >= 20) |>  # require minimum co-purchases for reliability
  arrange(desc(Lift))

# High lift = strong association. These are your "frequently bought together" pairs.
head(basket_lift, 20) |>
  select(Description.x, Description.y, TimesBoughtTogether, Lift)



# Q13: Which products should be stocked MORE heading into Q4?
# Compares Q4 sales share vs annual average — anything above 1.0 is Q4-heavy

q4_index <- df |>
  mutate(IsQ4 = Quarter == 4) |>
  group_by(Description) |>
  summarise(
    TotalRevenue = sum(Revenue),
    Q4Revenue    = sum(Revenue[IsQ4]),
    Q4Share      = Q4Revenue / TotalRevenue,
    .groups = "drop"
  ) |>
  filter(TotalRevenue > 1000) |>       # meaningful products only
  mutate(Q4Index = Q4Share / 0.25) |>  # 0.25 = expected share if sales were uniform
  arrange(desc(Q4Index))

# Q4Index >> 1.0 means this product is disproportionately a Q4 seller
head(q4_index, 15) |>
  ggplot(aes(x = reorder(Description, Q4Index), y = Q4Index)) +
  geom_col(fill = "coral") +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray40") +
  coord_flip() +
  labs(title = "Products Most Skewed Toward Q4 Sales",
       subtitle = "Index > 1.0 = sells more in Q4 than expected",
       x = NULL, y = "Q4 Sales Index") +
  theme_minimal()
