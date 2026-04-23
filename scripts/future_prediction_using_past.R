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


invisible(lapply(packages, function(pkg) {
    suppressMessages(
        suppressWarnings(
            suppressPackageStartupMessages(
                library(pkg, character.only = TRUE)
            )
        )
    )
}))




# ============================================= Start =====================================================

# LOAD DATA AND MODIFY THE MAIN DATA TABLE
db_path <- "database/clean_retail.db"  # Change the name and location of the file while executing
fig_path <- "figures"
con <- dbConnect(SQLite(), db_path)
retail <- dbGetQuery(con, "SELECT * FROM online_retail")
retail <- retail %>%
    rename_with(tolower) %>%
    mutate(invoice_date=as.Date(invoicedate))
    
# head(retail)
dbDisconnect(con)
cat("Database table Loaded. Total rows: ", nrow(retail))

colnames(retail)
head(retail)

# BUILD A DATAFRAME SHOWING ORDERS  AND REVENUE DAILY ALONG WITH SOME NEW FEATURES
demand_data <- retail %>%
    filter(country=="United Kingdom") %>%
    mutate(
        month=month(invoice_date, label=TRUE),
        day_of_the_week=wday(invoice_date, label=TRUE),
        quarter=as.factor(quarter(invoice_date)),
        is_weekend=as.factor(ifelse(wday(invoice_date) %in% c(1, 7), "Yes", "No")),
        week_of_the_year=week(invoice_date)
    ) %>%
    group_by(
        invoice_date,
        month,
        day_of_the_week,
        quarter,
        is_weekend,
        week_of_the_year
    )%>%
    summarise(
        total_quantity=sum(quantity),
        total_revenue=sum(totalprice),
        n_order=n_distinct(invoice),
        revenue_per_order=total_revenue/n_order,
        avg_order_size=total_quantity/n_order,
        .groups="drop"
    )


# ADD SPIKE LEVEL.IF THE QUANTITY FALLS IN TOP 25% OF QUANTITY ITS HIGH
spike_threshold <- quantile(demand_data$total_quantity, 0.75)
cat("Spike threshold: ", round(spike_threshold),  " units per day")

demand_data <- demand_data %>%
    mutate(
        demand_spike=as.factor(ifelse(total_quantity>=spike_threshold, "High", "Normal"))
    )



# ADD ADDITIONAL FEATURE THAT MIGHT HELP IMRPOVE THE MODELING
demand_features <- demand_data %>%
    arrange(invoice_date) %>%
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


# print(demand_features, n = 20, width = Inf)

main_dt <- demand_features %>%
    select(
        month, day_of_the_week, quarter, is_weekend, week_of_the_year,
        lag1_quantity, lag1_orders, lag1_revenue, day7_roll_quantity, day7_roll_order,
        weekxday, weekxweekend, day7rollxlag1, next_day_spike
    )%>%
    mutate(across(where(is.character), as.factor)) %>%
    na.omit

# print(main_dt, n=20, width=Inf)
# cat("Final modeling table: ", main_dt)



# SPLIT DATA INTO TEST, TRAIN, VAL
set.seed(192)
train_idx <- createDataPartition(main_dt$next_day_spike, p=0.8, list=FALSE)
train_data <- main_dt[train_idx, ]
test_data <- main_dt[-train_idx, ]



# MODEL 1: DECISION TREE
cat("Training decision tree model")
set.seed(193)
dec_tree <- rpart(
    next_day_spike ~ .,
    data=train_data,
    method='class',
    parms=list(loss=matrix(c(0, 3, 1, 0), nrow=2)),
    control=rpart.control(cp=0.001, maxdepth=5, minsplit=10)
)

# png("figures/decision_tree.png", width=1200, height=800)
# rpart.plot(
#     dec_tree,
#     type=4,
#     extra=104,
#     box.palette="RdYlGn",
#     main="Decision Tree: Will Tomorrow be a demand spike?"
# )
# dev.off()

pred_tree <- predict(dec_tree, test_data, type='class')
cm_tree <- confusionMatrix(pred_tree, test_data$next_day_spike, positive="High")

cat("Accuracy: ", round(cm_tree$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_tree$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_tree$byClass["Recall"] * 100, 1), "%\n")
print(cm_tree$table)

# ======================Decision Treee Result
# Accuracy:  79 %
# Precision:  61.1 %
# Recall:  37.9 %
#           Reference
# Prediction High Normal
#     High     11      7
#     Normal   18     83



# RANDOM FOREST + BAGGING 
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
cm_rf <- confusionMatrix(pred_rf, test_data$next_day_spike, positive="High")

cat("Accuracy: ", round(cm_rf$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_rf$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_rf$byClass["Recall"] * 100, 1), "%\n")
print(cm_rf$table)


# ======================Random Forest Result
# Accuracy:  87.4 %
# Precision:  79.2 %
# Recall:  65.5 %
#           Reference
# Prediction High Normal
#     High     19      5
#     Normal   10     85




# BOOSTING + CROSS VALIDATION 
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

# png("figures/boosting_variable_importance.png", width=1200, height=800)
# summary(
#     boost_model, n.trees=best_trees, main="Boosting: Variable Importance"
# )
# dev.off()


# ====================== Boosting and CV Result to find best number of trees
# Best number of trees (CV):  260   
# week_of_the_year     week_of_the_year 33.1794934
# day7_roll_order       day7_roll_order 20.6211601
# weekxday                     weekxday 12.9705129
# day7_roll_quantity day7_roll_quantity 12.8961820
# day_of_the_week       day_of_the_week 11.6233856
# day7rollxlag1           day7rollxlag1  2.8675081
# lag1_quantity           lag1_quantity  2.0525752
# lag1_revenue             lag1_revenue  1.1183716
# month                           month  1.0213795
# lag1_orders               lag1_orders  0.8276453
# quarter                       quarter  0.5818491
# weekxweekend             weekxweekend  0.2399372
# is_weekend                 is_weekend  0.0000000



boost_probs <- predict(boost_model, test_gbm, n.trees = best_trees, type = "response")
boost_pred  <- ifelse(boost_probs >= 0.3, "High", "Normal")
boost_pred  <- factor(boost_pred, levels = c("High", "Normal"))

cm_boost <- confusionMatrix(boost_pred, test_data$next_day_spike, positive = "High")

cat("Accuracy: ", round(cm_boost$overall["Accuracy"] * 100, 1), "%\n")
cat("Precision: ", round(cm_boost$byClass["Precision"] * 100, 1), "%\n")
cat("Recall: ", round(cm_boost$byClass["Recall"] * 100, 1), "%\n")
print(cm_boost$table)
y_true <- ifelse(test_gbm$next_day_spike == "High", 1, 0)
mse <- mean((y_true - boost_probs)^2)
mse

# ====================== Boosting and CV Test Results with λ = 0.5 
# Accuracy:  86.6 %
# Precision:  76 %
# Recall:  65.5 %
#           Reference
# Prediction High Normal
#     High     19      6
#     Normal   10     84
# MSE :  0.1126603


# ====================== Boosting and CV Test Results with λ = 0.3 
# Accuracy:  84 %
# Precision:  66.7 %
# Recall:  69 %
#           Reference
# Prediction High Normal
#     High     20     10
#     Normal    9     80
# MSE :  0.1126603





# MODEL COMPARISON
cat("MODEL COMPARISON")

results <- data.frame(
    model = c("Decision Tree", "Random Forest", "Boosting (GBM)"),
    accuracy  = round(c(cm_tree$overall["Accuracy"],
                        cm_rf$overall["Accuracy"],
                        cm_boost$overall["Accuracy"]) * 100, 1),
    precision = round(c(cm_tree$byClass["Precision"],
                        cm_rf$byClass["Precision"],
                        cm_boost$byClass["Precision"]) * 100, 1),
    recall = round(c(cm_tree$byClass["Recall"],
                        cm_rf$byClass["Recall"],
                        cm_boost$byClass["Recall"]) * 100, 1)
)

print(results)

# # Bar chart comparing all three models
# png("figures/model_comparison.png", width=1200, height=800)
# par(mar = c(5, 4, 4, 8), xpd = TRUE)
# bar_data <- t(as.matrix(results[, c("accuracy", "precision", "recall")]))
# colnames(bar_data) <- results$model

# barplot(
#     bar_data,
#     beside = TRUE,
#     col = c("steelblue", "coral", "seagreen"),
#     ylim = c(0, 110),
#     ylab = "Score (%)",
#     main = "Part 1: Model Comparison -  Predicting Demand Spikes",
#     cex.names = 0.85
# )
# legend("topright", inset = c(-0.28, 0),
#        legend = c("Accuracy", "Precision", "Recall"),
#        fill = c("steelblue", "coral", "seagreen"),
#        bty = "n", cex = 0.85)
# par(mar = c(5, 4, 4, 2), xpd = FALSE)
# dev.off()


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
cat("\nConclusion: Correctly predicting spike days and stocking accordingly\n")
cat("protects the revenue shown above from stockout losses.\n")
cat("Weeks", paste(head(spike_weeks$week_of_the_year, 5), collapse=", "),
    "are highest-risk — prioritise inventory build-up in those periods.\n")