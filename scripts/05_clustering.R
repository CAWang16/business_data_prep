if (!require("RSQLite", quietly = TRUE)) install.packages("RSQLite")
if (!require("dplyr", quietly = TRUE)) install.packages("dplyr")
if (!require("DBI", quietly = TRUE)) install.packages("DBI")
if (!require("RSQLite", quietly = TRUE)) install.packages("RSQLite")


library(dplyr)
library(DBI)
library(RSQLite)
library(lubridate)

db_path <- "database/clean_retail.db"
fig_path <- "figures"


# LOAD DATA
con <- dbConnect(SQLite(), db_path)
retail_full <- dbGetQuery(con, "
    SELECT 
        invoice_no, invoice_date, price, quantity, country,
        description, customer_id,
        is_cancellation_invoice, is_gift_voucher, is_free_item,
        is_shipping_fee, is_admin_invoice, is_inventory_adjustment
    FROM clean_product_sales
")
dbDisconnect(con)

retail_full <- retail_full %>%
    rename_with(tolower) %>%
    mutate(invoice_date_only = as.Date(invoice_date))


# FILTER TO CLEAN TRANSACTIONS
retail_customers <- retail_full %>%
    filter(
        !is.na(customer_id),
        is_cancellation_invoice == 0,
        is_admin_invoice == 0,
        is_inventory_adjustment == 0,
        is_gift_voucher == 0,
        is_shipping_fee == 0,
        is_free_item == 0,
        quantity > 0,
        price > 0,
        # country  == "United Kingdom"
    ) %>%
    mutate(line_revenue = price * quantity)

cat("Clean transactions:", nrow(retail_customers), "\n")
cat("Unique customers:", n_distinct(retail_customers$customer_id), "\n")


# BUILD CUSTOMER FEATURE MATRIX (RFM)
reference_date <- max(retail_customers$invoice_date_only) + 1

customer_rfm <- retail_customers %>%
    group_by(customer_id) %>%
    summarise(
        recency = as.numeric(reference_date - max(invoice_date_only)),
        frequency = n_distinct(invoice_no),
        monetary = sum(line_revenue),
        avg_order_value = monetary / frequency,
        avg_basket_size = sum(quantity) / frequency,
        n_products = n_distinct(description),
        .groups = "drop"
    ) %>%
    # Filtering out customer 16446 as they bought 80,995 units of a single product in one invoice which seems a bit extreme
    # and any customer where the monetary is less than 0
    filter(monetary>0, customer_id != 16446)

cat("Customers after cleaning:", nrow(customer_rfm), "\n")
cat("Unique customers: ", n_distinct(customer_rfm$customer_id), "\n")



# CHECK DISTRIBUTION OF THE FEATURES
# This confimes that our data is highly right skewed. Recency is better than the
# rest of the features
png(file.path(fig_path, "raw_nonlog_customer_rfm_distributions.png"), width = 1400, height = 900, res = 150)
par(mfrow = c(2, 3))
hist(customer_rfm$monetary, main = "Monetary", xlab = "£")
hist(customer_rfm$frequency, main = "Frequency", xlab = "Orders")
hist(customer_rfm$recency, main = "Recency", xlab = "Days")
hist(customer_rfm$avg_order_value, main = "Avg Order Value", xlab = "£")
hist(customer_rfm$avg_basket_size, main = "Avg Basket Size", xlab = "Units")
hist(customer_rfm$n_products, main = "N Products", xlab = "Count")
dev.off()
cat("Saved: raw_nonlog_customer_rfm_distributions.png\n")


# LOG TRANSFORM ALL FEATURE (EXCEPT RECENCY) TO CORRECT FOR RIGHT SKEW 
customer_rfm_log <- customer_rfm %>%
    mutate(
        monetary        = log1p(monetary),
        frequency       = log1p(frequency),
        avg_order_value = log1p(avg_order_value),
        avg_basket_size = log1p(avg_basket_size),
        n_products      = log1p(n_products)
        # recency left untransformed as the plot shows
        # it already captures two natural groups (recent vs lapsed)
        # which is useful signal for clustering
    )


# VERIFY TRANSFORMATION IMPROVED DISTRIBUTIONS
png(file.path(fig_path, "log_customer_rfm_distributions.png"), width = 1400, height = 900, res = 150)
par(mfrow = c(2, 3))
hist(customer_rfm_log$monetary, main = "Monetary (log)", xlab = "log(£)")
hist(customer_rfm_log$frequency, main = "Frequency (log)", xlab = "log(Orders)")
hist(customer_rfm_log$recency, main = "Recency (raw)", xlab = "Days")
hist(customer_rfm_log$avg_order_value, main = "Avg Order Value (log)", xlab = "log(£)")
hist(customer_rfm_log$avg_basket_size, main = "Avg Basket Size (log)", xlab = "log(Units)")
hist(customer_rfm_log$n_products, main = "N Products (log)", xlab = "log(Count)")
dev.off()
cat("Saved: log_customer_rfm_distributions.png\n")

#  PCA ON LOG-TRANSFORMED DATA
# Using log-transformed data instead of raw which is justified by right skew
# confirmed in histograms
customer_matrix <- customer_rfm_log %>% select(-customer_id) %>% as.matrix()

pr.out <- prcomp(customer_matrix, scale = TRUE)

# Scree plot
pve <- 100 * pr.out$sdev^2 / sum(pr.out$sdev^2)

png(file.path(fig_path, "customer_pca_scree.png"), width = 1200, height = 600, res = 150)
par(mfrow = c(1, 2))
plot(pve, type = "o", col = "blue",
     xlab = "Principal Component", ylab = "PVE (%)",
     main = "Customer PCA: Scree Plot")
plot(cumsum(pve), type = "o", col = "brown3",
     xlab = "Principal Component", ylab = "Cumulative PVE (%)",
     main = "Customer PCA: Cumulative Variance")
abline(h = 85, lty = 2, col = "grey50")
dev.off()
cat("Saved: customer_pca_scree.png\n")

# Print summary
cat("\nPCA Summary:\n")
print(summary(pr.out))

# Plot first two PC score vectors
png(file.path(fig_path, "customer_pc_scores.png"), width = 900, height = 800, res = 150)
plot(pr.out$x[, 1:2],
     pch = 20, col = "steelblue", cex = 0.7,
     xlab = "PC1", ylab = "PC2",
     main = "Customers: First Two Principal Component Score Vectors")
dev.off()
cat("Saved: customer_pc_scores.png\n")

# Choose number of PCs
m <- which(cumsum(pve) >= 85)[1]
cat("PCs explaining >=85% variance:", m, "\n")


# K-MEANS ON PC SCORES (log-transformed data)
# Trying K = 3, 4 and 5 and comparing tot.withinss
set.seed(197)
km.out3 <- kmeans(pr.out$x[, 1:m], centers = 3, nstart = 20)
km.out4 <- kmeans(pr.out$x[, 1:m], centers = 4, nstart = 20)
km.out5 <- kmeans(pr.out$x[, 1:m], centers = 5, nstart = 20)

cat("\nK=3 tot.withinss:", round(km.out3$tot.withinss, 1))
cat("\nK=4 tot.withinss:", round(km.out4$tot.withinss, 1))
cat("\nK=5 tot.withinss:", round(km.out5$tot.withinss, 1))
cat("\nK=3 between/total:", round(km.out3$betweenss / km.out3$totss * 100, 1), "%")
cat("\nK=4 between/total:", round(km.out4$betweenss / km.out4$totss * 100, 1), "%")
cat("\nK=5 between/total:", round(km.out5$betweenss / km.out5$totss * 100, 1), "%\n")

# The improvement from K=4 to K=5 is not significant, so we choose K = 4
km.out <- km.out4
K <- 4

cat("\nCustomer cluster sizes (K =", K, "):\n")
print(table(km.out$cluster))

# Plot clusters on first two PCs
png(file.path(fig_path, "customer_kmeans_pca.png"), width = 1000, height = 800, res = 150)
plot(pr.out$x[, 1:2],
     col  = (km.out$cluster + 1),
     pch  = 20, cex = 0.8,
     xlab = "PC1", ylab = "PC2",
     main = paste("K-Means Customer Clusters (K =", K, ") on PC Score Vectors"))
dev.off()
cat("Saved: customer_kmeans_pca.png\n")


# HIERARCHICAL CLUSTERING ON PC SCORES
set.seed(196)
n_hc <- min(300, nrow(pr.out$x))
hc_idx <- sample(nrow(pr.out$x), n_hc)
hc_data <- pr.out$x[hc_idx, 1:m]

data.dist <- dist(hc_data)

# Three linkage methods — as per Chapter 12 lab
hc.complete <- hclust(data.dist, method = "complete")
hc.average <- hclust(data.dist, method = "average")
hc.single <- hclust(data.dist, method = "single")

png(file.path(fig_path, "customer_dendrograms.png"), width = 1800, height = 700, res = 150)
par(mfrow = c(1, 3))
plot(hc.complete, main = "Complete Linkage", xlab = "", sub = "", labels = FALSE, hang = -1)
plot(hc.average, main = "Average Linkage", xlab = "", sub = "", labels = FALSE, hang = -1)
plot(hc.single, main = "Single Linkage", xlab = "", sub = "", labels = FALSE, hang = -1)
dev.off()
cat("Saved: customer_dendrograms.png\n")

# Cut dendrogram with complete linkage
hc.out <- hc.complete
hc.clusters <- cutree(hc.out, K)

cat("\nHierarchical cluster sizes:\n")
print(table(hc.clusters))

# Dendrogram with cut line
png(file.path(fig_path, "customer_dendrogram_cut.png"), width = 1200, height = 800, res = 150)
plot(hc.out,
     main = paste("Complete Linkage — Cut to", K, "Clusters (sample n =", n_hc, ")"),
     xlab = "", sub = "", labels = FALSE, hang = -1)
abline(h = (hc.out$height[length(hc.out$height) - K + 1] * 0.95),
       col = "red", lty = 2)
dev.off()
cat("Saved: customer_dendrogram_cut.png\n")


# COMPARE K-MEANS vs HIERARCHICAL
km.clusters.sample <- km.out$cluster[hc_idx]

cat("\nK-Means vs Hierarchical Clustering agreement (sample):\n")
print(table(KMeans = km.clusters.sample, HClust = hc.clusters))


# PROFILE SEGMENTS
# Profile uses original (non-log) values for interpretability
# so monetary shows real £ not log(£)
customer_rfm$segment <- km.out$cluster

segment_profiles <- customer_rfm %>%
    group_by(segment) %>%
    summarise(
        n_customers = n(),
        avg_recency = round(mean(recency), 0),
        avg_frequency = round(mean(frequency), 1),
        avg_monetary = round(mean(monetary), 0),
        avg_order_value = round(mean(avg_order_value), 0),
        avg_basket_size = round(mean(avg_basket_size), 1),
        avg_n_products  = round(mean(n_products), 0),
        .groups = "drop"
    ) %>%
    arrange(desc(avg_monetary))

cat("\n--- CUSTOMER SEGMENT PROFILES ---\n")
print(segment_profiles)

# Bar chart of average spend per segment
png(file.path(fig_path, "customer_segment_profiles.png"), width = 1200, height = 700, res = 150)
par(mar = c(5, 5, 4, 2))
barplot(
    segment_profiles$avg_monetary,
    names.arg = paste("Segment", segment_profiles$segment),
    col = c("#e74c3c", "#3498db", "#2ecc71", "#f39c12")[1:K],
    ylab = "Average Total Spend (£)",
    main = "Customer Segments: Average Monetary Value",
    ylim = c(0, max(segment_profiles$avg_monetary) * 1.2)
)
text(
    x = barplot(segment_profiles$avg_monetary, plot = FALSE),
    y = segment_profiles$avg_monetary + max(segment_profiles$avg_monetary) * 0.03,
    labels = paste0("n=", segment_profiles$n_customers,
                    "\nFreq=", segment_profiles$avg_frequency),
    cex = 0.85
)
dev.off()
cat("Saved: customer_segment_profiles.png\n")