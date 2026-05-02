# Install Packages if not already installed
if (!require("dplyr", quietly = TRUE)) install.packages("dplyr")
if (!require("lubridate", quietly = TRUE)) install.packages("lubridate")
if (!require("ggplot2", quietly = TRUE)) install.packages("ggplot2")
if (!require("rpart", quietly = TRUE)) install.packages("rpart")
if (!require("rpart.plot", quietly = TRUE)) install.packages("rpart.plot")
if (!require("caret", quietly = TRUE)) install.packages("caret")
if (!require("randomForest", quietly = TRUE)) install.packages("randomForest")
if (!require("zoo", quietly = TRUE)) install.packages("zoo")
if (!require("gbm", quietly = TRUE)) install.packages("gbm")
if (!require("DBI", quietly = TRUE)) install.packages("DBI")
if (!require("RSQLite", quietly = TRUE)) install.packages("RSQLite")


# Load packages and don't show the message in terminal showing that the library is loading
# while being executed
packages <- c("zoo", "lubridate", "dplyr", "ggplot2",
              "rpart", "rpart.plot", "caret", "randomForest",
              "RSQLite", "DBI")



# ============================================= Start =====================================================

# LOAD DATA AND MODIFY THE MAIN DATA TABLE
db_path <- "database/clean_retail.db"  # Change the name and location of the file while executing
fig_path <- "figures"
con <- dbConnect(SQLite(), db_path)
retail <- dbGetQuery(con, " SELECT invoice_no, invoice_date, price, quantity, country, description FROM clean_product_sales")
retail <- retail %>%
    rename_with(tolower) %>%
    mutate(invoice_date_only=as.Date(invoice_date))
    
# head(retail)
dbDisconnect(con)
cat("Database table Loaded. Total rows: ", nrow(retail))


colnames(retail)
head(retail)

# BUILD A DATAFRAME SHOWING ORDERS  AND REVENUE DAILY ALONG WITH SOME NEW FEATURES
demand_data <- retail %>%
    filter(country=="United Kingdom") %>%
    mutate(
        month=month(invoice_date_only, label=TRUE),
        day_of_the_week=wday(invoice_date_only, label=TRUE),
        quarter=as.factor(quarter(invoice_date_only)),
        is_weekend=as.factor(ifelse(wday(invoice_date_only) %in% c(1, 7), "Yes", "No")),
        week_of_the_year=week(invoice_date_only)
    ) %>%
    group_by(
        invoice_date_only,
        month,
        day_of_the_week,
        quarter,
        is_weekend,
        week_of_the_year
    )%>%
    summarise(
        total_quantity=sum(quantity),
        # total_revenue=sum(totalprice),
        total_revenue=sum(price),
        # n_order=n_distinct(invoice),
        n_order=n_distinct(invoice_no),
        revenue_per_order=total_revenue/n_order,
        avg_order_size=total_quantity/n_order,
        .groups="drop"
    )



demand_data_non_uk <- retail %>%
    filter(country != "United Kingdom")%>%
    mutate(
        month=month(invoice_date_only, label=TRUE),
        day_of_the_week=wday(invoice_date_only, label=TRUE),
        quarter=as.factor(quarter(invoice_date_only)),
        is_weekend=as.factor(ifelse(wday(invoice_date_only) %in% c(1, 7), "Yes", "No")),
        week_of_the_year=week(invoice_date_only)
    ) %>%
    group_by(
        invoice_date_only,
        month,
        day_of_the_week,
        quarter,
        is_weekend,
        week_of_the_year
    )%>%
    summarise(
        total_quantity=sum(quantity),
        # total_revenue=sum(totalprice),
        total_revenue=sum(price),
        # n_order=n_distinct(invoice),
        n_order=n_distinct(invoice_no),
        revenue_per_order=total_revenue/n_order,
        avg_order_size=total_quantity/n_order,
        .groups="drop"
    )





# ADD SPIKE LEVEL.IF THE QUANTITY FALLS IN TOP 25% OF QUANTITY ITS HIGH
spike_threshold <- quantile(demand_data$total_quantity, 0.75)
cat("UK Spike threshold: ", round(spike_threshold),  " units per day")

spike_threshold_non_uk <- quantile(demand_data_non_uk$total_quantity, 0.75)
cat("Non-UK Spike threshold: ", round(spike_threshold_non_uk), " units per day")






demand_data <- demand_data %>%
    mutate(
        demand_spike=as.factor(ifelse(total_quantity>=spike_threshold, "High", "Normal"))
    )

demand_data_non_uk <- demand_data_non_uk %>%
    mutate(
        demand_spike=as.factor(ifelse(total_quantity>=spike_threshold_non_uk, "High", "Normal"))
    )


# SPIKE DAYS PLOT
png(file.path(fig_path, "spike_days.png"), width = 1200, height = 800, res = 150)

ggplot(demand_data, aes(x = invoice_date_only, y = total_quantity, color = demand_spike)) +
    geom_point(alpha = 0.7, size = 2) +
    geom_line(color = "grey80", linewidth = 0.3, alpha = 0.5) +
    scale_color_manual(
        values = c("High" = "#e74c3c", "Normal" = "#3498db"),
        labels = c("High" = "Demand Spike", "Normal" = "Normal Day")
    ) +
    labs(
        title = "Daily Demand: Spike vs Normal Days (UK)",
        subtitle = paste("Spike threshold:", round(spike_threshold), "units/day (top 25%)"),
        x = "Date",
        y = "Total Units Sold",
        color = "Demand Level"
    ) +
    theme_minimal(base_size = 13) +
    theme(
        plot.title = element_text(face = "bold"),
        legend.position = "top"
    )

dev.off()
cat("Saved: ", file.path(fig_path, "spike_days.png"), "\n")


# ADD ADDITIONAL FEATURE THAT MIGHT HELP IMRPOVE THE MODELING
demand_features <- demand_data %>%
    arrange(invoice_date_only) %>%
    mutate(
        # Lags
        lag1_quantity=lag(total_quantity, 1),
        lag1_orders=lag(n_order, 1),
        lag1_revenue=lag(total_revenue, 1),

        # Rolling 7-day averages
        day7_roll_quantity=rollmean(total_quantity, k=7, fill=NA,align="right"),
        day7_roll_order=rollmean(n_order, k=7, fill=NA, align="right"),

        # Interaction terms
        weekxday=as.numeric(week_of_the_year) * as.numeric(day_of_the_week),
        weekxweekend=as.numeric(week_of_the_year) * as.numeric(is_weekend=="Yes"),
        day7rollxlag1=day7_roll_order*lag1_orders,

        next_day_spike=lead(demand_spike, 1)
    ) %>%
    filter(!is.na(lag1_quantity), !is.na(day7_roll_quantity), !is.na(next_day_spike))


demand_features_non_uk <- demand_data_non_uk %>%
    arrange(invoice_date_only) %>%
    mutate(
        # Lags
        lag1_quantity=lag(total_quantity, 1),
        lag1_orders=lag(n_order, 1),
        lag1_revenue=lag(total_revenue, 1),

        # Rolling 7-day averages
        day7_roll_quantity=rollmean(total_quantity, k=7, fill=NA,align="right"),
        day7_roll_order=rollmean(n_order, k=7, fill=NA, align="right"),

        # Interaction terms
        weekxday=as.numeric(week_of_the_year) * as.numeric(day_of_the_week),
        weekxweekend=as.numeric(week_of_the_year) * as.numeric(is_weekend=="Yes"),
        day7rollxlag1=day7_roll_order*lag1_orders,

        next_day_spike=lead(demand_spike, 1)
    ) %>%
    filter(!is.na(lag1_quantity), !is.na(day7_roll_quantity), !is.na(next_day_spike))



main_dt <- demand_features %>%
    select(
        month, day_of_the_week, quarter, is_weekend, week_of_the_year,
        lag1_quantity, lag1_orders, lag1_revenue, day7_roll_quantity, day7_roll_order,
        weekxday, weekxweekend, day7rollxlag1, next_day_spike
    )%>%
    mutate(across(where(is.character), as.factor)) %>%
    na.omit

main_dt_non_uk <- demand_features_non_uk %>%
    select(
        month, day_of_the_week, quarter, is_weekend, week_of_the_year,
        lag1_quantity, lag1_orders, lag1_revenue, day7_roll_quantity, day7_roll_order,
        weekxday, weekxweekend, day7rollxlag1, next_day_spike 
    )




# SPLIT DATA INTO TEST, TRAIN, VAL
set.seed(192)
train_idx <- createDataPartition(main_dt$next_day_spike, p=0.8, list=FALSE)
train_data <- main_dt[train_idx, ]
test_data <- main_dt[-train_idx, ]

test_data_non_uk <- main_dt_non_uk



# ==================================================MODEL 1: DECISION TREE ======================================
cat("Training decision tree model")
set.seed(193)
dec_tree <- rpart(
    next_day_spike ~ .,
    data=train_data,
    method='class',
    parms=list(loss=matrix(c(0, 3, 1, 0), nrow=2)),
    control=rpart.control(cp=0.001, maxdepth=5, minsplit=10)
)

png("figures/decision_tree.png", width=1200, height=800)
rpart.plot(
    dec_tree,
    type=4,
    extra=104,
    box.palette="RdYlGn",
    main="Decision Tree: Will Tomorrow be a demand spike?"
)
dev.off()

pred_tree <- predict(dec_tree, test_data, type='class')
pred_tree_non_uk <- predict(dec_tree, test_data_non_uk, type='class')
cm_tree <- confusionMatrix(pred_tree, test_data$next_day_spike, positive="High")
cm_tree2 <- confusionMatrix(pred_tree_non_uk, test_data_non_uk$next_day_spike, positive="High")

cat("Accuracy: ", round(cm_tree$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_tree$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_tree$byClass["Recall"] * 100, 1), "%\n")
print(cm_tree$table)


cat("Results for NON-UK data")
cat("Accuracy: ", round(cm_tree2$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_tree2$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_tree2$byClass["Recall"] * 100, 1), "%\n")
print(cm_tree2$table)





png(file.path(fig_path, "dt_variable_importance.png"), width = 1200, height = 800, res = 150)

dt_imp <- data.frame(
    variable   = names(dec_tree$variable.importance),
    importance = dec_tree$variable.importance
) %>%
    arrange(desc(importance))

ggplot(dt_imp, aes(x = reorder(variable, importance), y = importance)) +
    geom_col(fill = "#3498db", alpha = 0.85) +
    coord_flip() +
    labs(
        title = "Decision Tree: Variable Importance (Gini-based)",
        subtitle = "Higher = more splits on this variable weighted by node purity gain",
        x = NULL,
        y = "Importance (Gini Impurity Reduction)"
    ) +
    theme_minimal(base_size = 13) +
    theme(plot.title = element_text(face = "bold"))

dev.off()
cat("Saved: ", file.path(fig_path, "dt_variable_importance.png"), "\n")





# ============================================ MODEL 2: RANDOM FOREST + BAGGING  ======================================
 
set.seed(194)
cat("Training random forest model")
rand_for_model <- randomForest(
    next_day_spike ~ .,
    data=train_data,
    ntree=500,
    importance=TRUE
)

# png("figures/rf_variable_importance.png", width = 1200, height = 800, res = 150)
# varImpPlot(rand_for_model, main="Random Forest: Variable Importance for Demand Spike")
# dev.off()
pred_rf <- predict(rand_for_model, test_data)
pred_rf_non_uk <- predict(rand_for_model, test_data_non_uk)
cm_rf <- confusionMatrix(pred_rf, test_data$next_day_spike, positive="High")
cm_rf2 <- confusionMatrix(pred_rf_non_uk, test_data_non_uk$next_day_spike, positive="High")

cat("Accuracy: ", round(cm_rf$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_rf$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_rf$byClass["Recall"] * 100, 1), "%\n")
print(cm_rf$table)

cat("Results for NON-UK data")
cat("Accuracy: ", round(cm_rf2$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_rf2$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_rf2$byClass["Recall"] * 100, 1), "%\n")
print(cm_rf2$table)



png(file.path(fig_path, "rf_variable_importance.png"), width = 1200, height = 900, res = 150)

rf_imp <- as.data.frame(importance(rand_for_model)) %>%
    tibble::rownames_to_column("variable") %>%
    rename(
        MeanDecreaseAccuracy = MeanDecreaseAccuracy,
        MeanDecreaseGini = MeanDecreaseGini
    ) %>%
    tidyr::pivot_longer(
        cols = c(MeanDecreaseAccuracy, MeanDecreaseGini),
        names_to = "metric",
        values_to = "importance"
    ) %>%
    mutate(metric = recode(metric,
        "MeanDecreaseAccuracy" = "Mean Decrease Accuracy",
        "MeanDecreaseGini" = "Mean Decrease Gini"
    ))

ggplot(rf_imp, aes(x = reorder(variable, importance), y = importance, fill = metric)) +
    geom_col(show.legend = FALSE, alpha = 0.85) +
    coord_flip() +
    facet_wrap(~metric, scales = "free_x") +
    scale_fill_manual(values = c("Mean Decrease Accuracy" = "#e74c3c",
                                  "Mean Decrease Gini"     = "#2ecc71")) +
    labs(
        title = "Random Forest: Variable Importance",
        subtitle = "Left: impact on accuracy if removed | Right: Gini impurity reduction across trees",
        x  = NULL,
        y  = "Importance"
    ) +
    theme_minimal(base_size = 12) +
    theme(
        plot.title  = element_text(face = "bold"),
        strip.text  = element_text(face = "bold")
    )

dev.off()
cat("Saved: ", file.path(fig_path, "rf_variable_importance.png"), "\n")


# ============================================ MODEL 3: BOOSTING + CROSS VALIDATION  ======================================
cat("Training with Boosting and CV")


# Converting the target to 0/1
train_gbm <- train_data %>%
    mutate(
        spike=ifelse(next_day_spike=="High", 1, 0)
    )

test_gbm <- test_data %>%
    mutate(
        spike=ifelse(next_day_spike=="High", 1, 0)
    )

test_gbm_non_uk <- test_data_non_uk %>%
    mutate(
        spike=ifelse(next_day_spike=="High", 1, 0)
    )

set.seed(195)
boost_model <- gbm(
    spike ~ month + day_of_the_week + quarter + is_weekend + week_of_the_year + lag1_quantity + lag1_orders +
    lag1_revenue + day7_roll_quantity + day7_roll_order + weekxday + weekxweekend + day7rollxlag1,
    data=train_gbm,
    distribution="bernoulli",
    n.trees=1000,
    shrinkage=0.01,
    interaction.depth=2,
    cv.folds=5,
    verbose=FALSE
)

best_trees <- gbm.perf(boost_model, method="cv")
cat("Best number of trees (CV): ", best_trees)



boost_probs <- predict(boost_model, test_gbm, n.trees = best_trees, type = "response")
boost_probs_non_uk <- predict(boost_model, test_gbm_non_uk, n.trees = best_trees, type="response")
boost_pred  <- ifelse(boost_probs >= 0.5, "High", "Normal")
boost_pred  <- factor(boost_pred, levels = c("High", "Normal"))
boost_pred_low  <- ifelse(boost_probs >= 0.3, "High", "Normal")
boost_pred_low  <- factor(boost_pred_low, levels = c("High", "Normal"))


boost_pred_non_uk  <- ifelse(boost_probs_non_uk >= 0.5, "High", "Normal")
boost_pred_non_uk  <- factor(boost_pred_non_uk, levels = c("High", "Normal"))
boost_pred_non_uk_low  <- ifelse(boost_probs_non_uk >= 0.3, "High", "Normal")
boost_pred_non_uk_low  <- factor(boost_pred_non_uk_low, levels = c("High", "Normal"))

cm_boost <- confusionMatrix(boost_pred, test_data$next_day_spike, positive = "High")
cm_boost2 <- confusionMatrix(boost_pred_non_uk, test_data_non_uk$next_day_spike, positive="High")

cm_boost_low <- confusionMatrix(boost_pred_low, test_data$next_day_spike, positive = "High")
cm_boost2_low <- confusionMatrix(boost_pred_non_uk_low, test_data_non_uk$next_day_spike, positive="High")

cat("RESULTS FOR UK DATA WITH λ = 0.5 \n")
cat("Accuracy: ", round(cm_boost$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_boost$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_boost$byClass["Recall"] * 100, 1), "%\n")
print(cm_boost$table)
y_true <- ifelse(test_gbm$next_day_spike == "High", 1, 0)
mse <- mean((y_true - boost_probs)^2)
mse


cat("RESULTS FOR UK DATA WITH λ = 0.3 \n")
cat("Accuracy: ", round(cm_boost_low$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_boost_low$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_boost_low$byClass["Recall"] * 100, 1), "%\n")
print(cm_boost_low$table)
y_true <- ifelse(test_gbm$next_day_spike == "High", 1, 0)
mse <- mean((y_true - boost_probs)^2)
mse



cat("RESULT FOR NON-UK DATA FOR λ = 0.5 \n")
cat("Accuracy: ", round(cm_boost2$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_boost2$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_boost2$byClass["Recall"] * 100, 1), "%\n")
print(cm_boost2$table)
y_true <- ifelse(test_gbm_non_uk$next_day_spike == "High", 1, 0)
mse <- mean((y_true - boost_probs_non_uk)^2)
mse



cat("RESULT FOR NON-UK DATA FOR λ = 0.3 \n")
cat("Accuracy: ", round(cm_boost2_low$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_boost2_low$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_boost2_low$byClass["Recall"] * 100, 1), "%\n")
print(cm_boost2_low$table)
y_true <- ifelse(test_gbm_non_uk$next_day_spike == "High", 1, 0)
mse <- mean((y_true - boost_probs_non_uk)^2)
mse




png(file.path(fig_path, "gbm_variable_importance.png"), width = 1200, height = 800, res = 150)

gbm_imp <- summary(boost_model, n.trees = best_trees, plotit = FALSE) %>%
    rename(variable = var, importance = rel.inf)

ggplot(gbm_imp, aes(x = reorder(variable, importance), y = importance)) +
    geom_col(fill = "#9b59b6", alpha = 0.85) +
    geom_text(aes(label = round(importance, 1)), hjust = -0.1, size = 3.5) +
    coord_flip(clip = "off") +
    labs(
        title = "GBM Boosting: Relative Influence",
        subtitle = "Percentage contribution of each variable to reducing loss across all trees",
        x = NULL,
        y = "Relative Influence (%)"
    ) +
    theme_minimal(base_size = 13) +
    theme(plot.title = element_text(face = "bold"))

dev.off()
cat("Saved: ", file.path(fig_path, "gbm_variable_importance.png"), "\n")




# MODEL COMPARISON
cat("MODEL COMPARISON")

results <- data.frame(
    model = c("Decision Tree", "Random Forest", "Boosting (GBM)"),
    accuracy  = round(c(cm_tree$overall["Accuracy"],
                        cm_rf$overall["Accuracy"],
                        cm_boost_low$overall["Accuracy"]) * 100, 1),
    precision = round(c(cm_tree$byClass["Precision"],
                        cm_rf$byClass["Precision"],
                        cm_boost_low$byClass["Precision"]) * 100, 1),
    recall = round(c(cm_tree$byClass["Recall"],
                        cm_rf$byClass["Recall"],
                        cm_boost_low$byClass["Recall"]) * 100, 1)
)

print(results)

# Bar chart comparing all three models
png("figures/model_comparison.png", width=1200, height=800)
par(mar = c(5, 4, 4, 8), xpd = TRUE)
bar_data <- t(as.matrix(results[, c("accuracy", "precision", "recall")]))
colnames(bar_data) <- results$model

barplot(
    bar_data,
    beside = TRUE,
    col = c("steelblue", "coral", "seagreen"),
    ylim = c(0, 110),
    ylab = "Score (%)",
    main = "Part 1: Model Comparison -  Predicting Demand Spikes",
    cex.names = 0.85
)
legend("topright", inset = c(-0.28, 0),
       legend = c("Accuracy", "Precision", "Recall"),
       fill = c("steelblue", "coral", "seagreen"),
       bty = "n", cex = 0.85)
par(mar = c(5, 4, 4, 2), xpd = FALSE)
dev.off()


cat("\n--- STOCKING RECOMMENDATIONS FROM BEST MODEL ---\n")

spike_weeks <- test_data %>%
    mutate(predicted_spike = boost_pred) %>%
    filter(predicted_spike == "High") %>%
    group_by(week_of_the_year) %>%
    summarise(
        predicted_spike_days = n(),
        .groups = "drop"
    ) %>%
    arrange(desc(predicted_spike_days))

print(spike_weeks)

# Revenue at risk if spikes are missed (missed spike = potential stockout)
spike_revenue <- demand_features %>%
    filter(demand_spike == "High") %>%
    summarise(
        avg_spike_revenue  = round(mean(total_revenue), 2),
        total_spike_days   = n(),
        total_spike_revenue = round(sum(total_revenue), 2)
    )

cat("\nAverage revenue on a spike day: £", spike_revenue$avg_spike_revenue, "\n")
cat("Total spike days in dataset: ", spike_revenue$total_spike_days, "\n")
cat("Total revenue on spike days: £", spike_revenue$total_spike_revenue, "\n")


# Compare means of key features
uk_summary <- demand_features %>%
  summarise(across(c(total_quantity, n_order, total_revenue, day7_roll_quantity), 
                 \(x) mean(x, na.rm = TRUE))) %>%
  mutate(group = "UK")

non_uk_summary <- demand_features_non_uk %>%
  summarise(across(c(total_quantity, n_order, total_revenue, day7_roll_quantity), 
                 \(x) mean(x, na.rm = TRUE))) %>%
  mutate(group = "Non-UK")

bind_rows(uk_summary, non_uk_summary)