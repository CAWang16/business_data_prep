# "If bought X, buy Y" -> Association Rules (Apriori)

# ── SETUP ──────────────────────────────────────────────────────────────────────
if (!require("RSQLite",    quietly = TRUE)) install.packages("RSQLite")
if (!require("dplyr",      quietly = TRUE)) install.packages("dplyr")
if (!require("lubridate",  quietly = TRUE)) install.packages("lubridate")
if (!require("ggplot2",    quietly = TRUE)) install.packages("ggplot2")
if (!require("stringr",    quietly = TRUE)) install.packages("stringr")
if (!require("arules",     quietly = TRUE)) install.packages("arules")
if (!require("arulesViz",  quietly = TRUE)) install.packages("arulesViz")

# setting correct wd()
if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  setwd(file.path(dirname(rstudioapi::getActiveDocumentContext()$path), ".."))
} else {
  script_path <- normalizePath(sub("--file=", "", commandArgs(trailingOnly = FALSE)[
    grep("--file=", commandArgs(trailingOnly = FALSE))
  ]))
  setwd(file.path(dirname(script_path), ".."))
}

library(RSQLite)
library(dplyr)
library(lubridate)
library(ggplot2)
library(stringr)
library(arules)      # Apriori algorithm
library(arulesViz)   # Rule visualization


# setting up db
db_path <- "database/clean_retail.db"
fig_path <- "figures"

con <- dbConnect(RSQLite::SQLite(), db_path)

df <- dbReadTable(con, "clean_product_sales") |>
  mutate(
    invoice_date = as.POSIXct(invoice_date, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"),
    Revenue      = quantity * price
  )

dbDisconnect(con)

# ── METHOD ─────────────────────────────────────────────────────────────────────
# Apriori algorithm finds association rules of the form "if a customer buys
# product X, they are likely to also buy product Y."
# Three key metrics:
#   - Support:    how often the pair appears together across all baskets
#   - Confidence: P(Y | X) — given X was bought, how often was Y also bought
#   - Lift:       confidence / expected confidence — lift > 1 means the
#                 association is stronger than random chance
#
# Train/test strategy:
#   - Rules learned from UK transactions only (training set)
#   - Rules validated against non-UK transactions (out-of-distribution test)
# Rationale: UK is the dominant market; non-UK serves as an OOD validation set
# to assess international generalisability.

# ── STEP 1: build transaction lists ───────────────────────────────────────────
# UK = training set
uk_transactions <- df |>
  filter(country == "United Kingdom") |>
  dplyr::select(invoice_no, description) |>
  distinct() |>
  group_by(invoice_no) |>
  summarise(items = list(description), .groups = "drop")

# non-UK = out-of-distribution test set
nouk_transactions <- df |>
  filter(country != "United Kingdom") |>
  dplyr::select(invoice_no, description) |>
  distinct() |>
  group_by(invoice_no) |>
  summarise(items = list(description), .groups = "drop")

cat("UK invoices (train):     ", nrow(uk_transactions), "\n")
cat("non-UK invoices (test):  ", nrow(nouk_transactions), "\n")

# ── STEP 2: convert to arules transaction format ───────────────────────────────
uk_trans   <- as(uk_transactions$items, "transactions")
nouk_trans <- as(nouk_transactions$items, "transactions")

cat("\nUK transaction summary:\n")
summary(uk_trans)

# ── STEP 3: fit Apriori on UK transactions ────────────────────────────────────
# supp  = item pair must appear in at least 1% of UK baskets
# conf  = rule must be correct at least 20% of the time
# minlen = 2 ensures at least one antecedent and one consequent
rules <- apriori(
  uk_trans,
  parameter = list(
    supp   = 0.01,
    conf   = 0.20,
    minlen = 2
  )
)

cat("\nRules summary:\n")
summary(rules)

# Top 20 rules by lift
cat("\nTop 20 rules by lift:\n")
inspect(sort(rules, by = "lift")[1:20])

# ── STEP 4: validate on non-UK transactions ────────────────────────────────────
# Check whether UK-derived rules also hold in non-UK markets
# A rule "holds" in non-UK if its confidence is still >= 0.20 there
rules_df <- as(rules, "data.frame")

# Extract LHS and RHS product names cleanly
rules_df$lhs_clean <- gsub("\\{|\\}", "", rules_df$rules) |>
  gsub(" =>.*", "", x = _) |>
  trimws()

rules_df$rhs_clean <- gsub(".*=> \\{|\\}", "", rules_df$rules) |>
  trimws()

# For each rule, compute confidence in non-UK data
nouk_item_matrix <- as(nouk_trans, "matrix")

compute_nouk_confidence <- function(lhs, rhs, item_matrix) {
  if (!(lhs %in% colnames(item_matrix)) || !(rhs %in% colnames(item_matrix))) {
    return(NA)
  }
  lhs_present  <- item_matrix[, lhs]
  rhs_present  <- item_matrix[, rhs]
  both_present <- lhs_present & rhs_present
  if (sum(lhs_present) == 0) return(NA)
  sum(both_present) / sum(lhs_present)
}

cat("\nComputing non-UK confidence for top rules...\n")
top_rules <- rules_df |>
  arrange(desc(lift)) |>
  head(50)

top_rules$nouk_confidence <- mapply(
  compute_nouk_confidence,
  top_rules$lhs_clean,
  top_rules$rhs_clean,
  MoreArgs = list(item_matrix = nouk_item_matrix)
)

top_rules$confidence_drop <- top_rules$confidence - top_rules$nouk_confidence

cat("\nTop 20 rules — UK vs non-UK confidence:\n")
print(
  top_rules |>
    dplyr::select(rules, support, confidence, lift, nouk_confidence, confidence_drop) |>
    head(20)
)

# ── STEP 5: visualize ─────────────────────────────────────────────────────────
# Scatter plot: support vs confidence, sized by lift
png(file.path(fig_path, "association_rules_supp_v_conf.png"), width = 1200, height = 600, res = 150)
plot(rules,
     measure  = c("support", "confidence"),
     shading  = "lift",
     main     = "Association Rules: Support vs Confidence (shaded by Lift)")
dev.off()

# Network graph of top 20 rules by lift
png(file.path(fig_path, "top_20_co-purchase_rules_lift.png"), width = 1200, height = 600, res = 150)
plot(sort(rules, by = "lift")[1:20],
     method = "graph",
     main   = "Top 20 Co-Purchase Rules by Lift")
dev.off()

# ── STEP 6: export rules for recommend.py ─────────────────────────────────────
export_rules <- as(rules, "data.frame") |>
  arrange(desc(lift))

# Clean up LHS and RHS for Python lookup
export_rules$LHS <- gsub("\\{|\\}", "", export_rules$rules) |>
  gsub(" =>.*", "", x = _) |>
  trimws()

export_rules$RHS <- gsub(".*=> \\{|\\}", "", export_rules$rules) |>
  trimws()

export_rules <- export_rules |>
  dplyr::select(LHS, RHS, support, confidence, lift) |>
  arrange(desc(lift))

write.csv(export_rules, "data/processed/association_rules.csv", row.names = FALSE)
cat("\nExported", nrow(export_rules), "rules to data/processed/association_rules.csv\n")
cat("Run Next_likely_product.py to query recommendations interactively.\n")
