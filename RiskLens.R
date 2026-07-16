# =============================================================================================
# RiskLens Analytics: Credit Default Risk Modeling & Portfolio Intelligence Dashboard
# =============================================================================================


# =============================================================================================
# 1. LOAD PACKAGES
# =============================================================================================
library(tidyverse)
library(here)
library(broom)
library(car)
library(scales)
library(pROC)
library(ranger)


# =====================================================================================
# 2. FILE PATHS
# =====================================================================================
loan_path <- here("accepted_2007_to_2018Q4.csv")


# =====================================================================================
# 3. READ DATA
# =====================================================================================
loan <- readr::read_csv(loan_path, show_col_types = FALSE)

cols_needed <- c('loan_amnt', 'term', 'int_rate', 'grade', 'sub_grade', 'annual_inc',
                 'dti', 'emp_length', 'home_ownership', 'purpose', 'verification_status',
                 'delinq_2yrs', 'inq_last_6mths', 'open_acc', 'pub_rec', 'revol_bal',
                 'revol_util', 'total_acc', 'loan_status', 'issue_d')

loan <- loan %>% select(all_of(cols_needed))

glimpse(loan)


# =====================================================================================
# 4. CLEAN DATA
# =====================================================================================
colMeans(is.na(loan)) * 100

loan_clean <- loan %>% drop_na()


# =====================================================================================
# 5a. CONVERT DATA TYPES
# =====================================================================================
loan_clean <- loan_clean %>%
  mutate(
    term = as.numeric(str_replace(str_trim(term), " months", "")),
    emp_length = case_when(
      emp_length == "< 1 year"  ~ 0,
      emp_length == "1 year"    ~ 1,
      emp_length == "2 years"   ~ 2,
      emp_length == "3 years"   ~ 3,
      emp_length == "4 years"   ~ 4,
      emp_length == "5 years"   ~ 5,
      emp_length == "6 years"   ~ 6,
      emp_length == "7 years"   ~ 7,
      emp_length == "8 years"   ~ 8,
      emp_length == "9 years"   ~ 9,
      emp_length == "10+ years" ~ 10,
      TRUE ~ NA_real_
    ),
    issue_d = my(issue_d)
  )

sum(is.na(loan_clean$term))
sum(is.na(loan_clean$emp_length))
sum(is.na(loan_clean$issue_d))

glimpse(loan_clean)


# =====================================================================================
# 5b. FILTER OUT IMMATURE LOANS
# =====================================================================================
data_cutoff <- as.Date("2018-12-31")

loan_clean <- loan_clean %>%
  mutate(expected_end = issue_d %m+% months(term)) %>%
  filter(expected_end <= data_cutoff)

nrow(loan_clean)
range(loan_clean$issue_d)


# =====================================================================================
# 6. EXPLORATORY ANALYSIS: GRADE & SUB-GRADE DISTRIBUTION
# =====================================================================================
grade_count <- loan_clean %>% count(grade) %>% arrange(grade)
print(grade_count)

subgrade_count <- loan_clean %>% count(sub_grade) %>% arrange(sub_grade)
print(subgrade_count)

ggplot(loan_clean, aes(x = grade, fill = grade)) +
  geom_bar() +
  labs(title = "Number of Loans by Grade",
       x = "Loan Grade",
       y = "Number of Loans") +
  theme_minimal() +
  theme(legend.position = "none") +
  scale_y_continuous(labels = comma)

ggplot(loan_clean, aes(x = sub_grade, fill = grade)) +
  geom_bar() +
  labs(title = "Number of Loans by Sub-Grade",
       x = "Loan Sub-Grade",
       y = "Number of Loans") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
  scale_y_continuous(labels = comma)


# =====================================================================================
# 7. DEFINE TARGET VARIABLE
# =====================================================================================
loan_model <- loan_clean %>%
  filter(loan_status %in% c("Fully Paid", "Charged Off", "Default", "Late (31-120 days)")) %>%
  mutate(target = if_else(loan_status %in% c("Charged Off", "Default", "Late (31-120 days)"), 1, 0))

table(loan_model$target)
prop.table(table(loan_model$target)) * 100

ggplot(loan_model, aes(x = factor(target, labels = c("Good (Fully Paid)", "Bad (Default/Charged Off/Late)")))) +
  geom_bar(fill = c("#2ca25f", "#de2d26")) +
  labs(title = "Target Variable Distribution",
       x = "Loan Outcome",
       y = "Number of Loans") +
  theme_minimal() +
  scale_y_continuous(labels = comma)


# =====================================================================================
# 8. TIME-BASED TRAIN / VALIDATION / TEST SPLIT
# =====================================================================================
cutoffs <- quantile(loan_model$issue_d, probs = c(0.70, 0.85), type = 1)
train_cutoff <- as.Date(cutoffs[1])
valid_cutoff <- as.Date(cutoffs[2])

train_cutoff
valid_cutoff

train_data <- loan_model %>% filter(issue_d <= train_cutoff)
valid_data <- loan_model %>% filter(issue_d > train_cutoff & issue_d <= valid_cutoff)
test_data  <- loan_model %>% filter(issue_d > valid_cutoff)

nrow(train_data)
nrow(valid_data)
nrow(test_data)

loan_model %>%
  mutate(issue_month = floor_date(issue_d, "month")) %>%
  count(issue_month) %>%
  ggplot(aes(x = issue_month, y = n)) +
  geom_line(color = "#3182bd") +
  geom_vline(xintercept = c(train_cutoff, valid_cutoff), linetype = "dashed", color = "red") +
  labs(title = "Loan Volume Over Time (Train / Validation / Test Boundaries)",
       x = "Issue Month",
       y = "Number of Loans") +
  theme_minimal() +
  scale_y_continuous(labels = comma)


# =====================================================================================
# 9. EXPORT TABLES FOR TABLEAU / POWER BI
# =====================================================================================
dir.create(here("outputs"), showWarnings = FALSE)

write_csv(grade_count, here("outputs", "grade_count.csv"))
write_csv(subgrade_count, here("outputs", "subgrade_count.csv"))
write_csv(loan_model, here("outputs", "loan_model_data.csv"))


# =====================================================================================
# 10. PREPARE CATEGORICAL VARIABLES
# =====================================================================================
train_data <- train_data %>%
  mutate(
    home_ownership       = factor(home_ownership),
    purpose              = factor(purpose),
    verification_status  = factor(verification_status)
  )

valid_data <- valid_data %>%
  mutate(
    home_ownership       = factor(home_ownership, levels = levels(train_data$home_ownership)),
    purpose              = factor(purpose, levels = levels(train_data$purpose)),
    verification_status  = factor(verification_status, levels = levels(train_data$verification_status))
  )

test_data <- test_data %>%
  mutate(
    home_ownership       = factor(home_ownership, levels = levels(train_data$home_ownership)),
    purpose              = factor(purpose, levels = levels(train_data$purpose)),
    verification_status  = factor(verification_status, levels = levels(train_data$verification_status))
  )

sum(is.na(valid_data$purpose))
sum(is.na(test_data$purpose))


# =====================================================================================
# 11. DEFINE FEATURE SETS
# =====================================================================================
formula_A <- target ~ loan_amnt + term + annual_inc + dti + emp_length +
  home_ownership + purpose + verification_status + delinq_2yrs +
  inq_last_6mths + open_acc + pub_rec + revol_bal + revol_util + total_acc

formula_B <- target ~ loan_amnt + term + int_rate + annual_inc + dti + emp_length +
  home_ownership + purpose + verification_status + delinq_2yrs +
  inq_last_6mths + open_acc + pub_rec + revol_bal + revol_util + total_acc


# =====================================================================================
# 12. COLLAPSE RARE CATEGORIES
# =====================================================================================
train_data <- train_data %>%
  mutate(home_ownership = fct_lump_min(home_ownership, min = 500, other_level = "OTHER"))

valid_data <- valid_data %>%
  mutate(home_ownership = factor(home_ownership, levels = levels(train_data$home_ownership)))

test_data <- test_data %>%
  mutate(home_ownership = factor(home_ownership, levels = levels(train_data$home_ownership)))

table(train_data$home_ownership)

train_data <- train_data %>%
  mutate(purpose = fct_lump_min(purpose, min = 500, other_level = "other_misc"))

valid_data <- valid_data %>%
  mutate(purpose = factor(purpose, levels = levels(train_data$purpose)))

test_data <- test_data %>%
  mutate(purpose = factor(purpose, levels = levels(train_data$purpose)))

table(train_data$purpose)


# =====================================================================================
# 13. TRAIN LOGISTIC REGRESSION (Version A and Version B)
# =====================================================================================
model_A <- glm(formula_A, data = train_data, family = binomial)
model_B <- glm(formula_B, data = train_data, family = binomial)

tidy(model_A)
tidy(model_B)


# =====================================================================================
# 14. EVALUATE LOGISTIC REGRESSION ON VALIDATION SET
# =====================================================================================
valid_data <- valid_data %>%
  mutate(
    pred_prob_A = predict(model_A, newdata = valid_data, type = "response"),
    pred_prob_B = predict(model_B, newdata = valid_data, type = "response")
  )

roc_A <- roc(valid_data$target, valid_data$pred_prob_A)
roc_B <- roc(valid_data$target, valid_data$pred_prob_B)

auc(roc_A)
auc(roc_B)

ggroc(list(Version_A = roc_A, Version_B = roc_B)) +
  labs(title = "ROC Curve Comparison: Model Without vs. With int_rate",
       x = "Specificity", y = "Sensitivity", color = "Model") +
  theme_minimal()


# =====================================================================================
# 15. TRAIN RANDOM FOREST (Version A and Version B, tuned mtry = 3)
# =====================================================================================
train_data <- train_data %>% mutate(target_factor = factor(target, labels = c("Good", "Bad")))

set.seed(42)
rf_A <- ranger(
  formula = target_factor ~ loan_amnt + term + annual_inc + dti + emp_length +
    home_ownership + purpose + verification_status + delinq_2yrs +
    inq_last_6mths + open_acc + pub_rec + revol_bal + revol_util + total_acc,
  data = train_data,
  probability = TRUE,
  importance = "impurity",
  mtry = 3,
  num.trees = 300,
  seed = 42
)

set.seed(42)
rf_B <- ranger(
  formula = target_factor ~ loan_amnt + term + int_rate + annual_inc + dti + emp_length +
    home_ownership + purpose + verification_status + delinq_2yrs +
    inq_last_6mths + open_acc + pub_rec + revol_bal + revol_util + total_acc,
  data = train_data,
  probability = TRUE,
  importance = "impurity",
  mtry = 3,
  num.trees = 300,
  seed = 42
)

sort(rf_A$variable.importance, decreasing = TRUE)
sort(rf_B$variable.importance, decreasing = TRUE)


# =====================================================================================
# 16. EVALUATE RANDOM FOREST ON VALIDATION SET
# =====================================================================================
pred_rf_A <- predict(rf_A, data = valid_data)$predictions[, "Bad"]
pred_rf_B <- predict(rf_B, data = valid_data)$predictions[, "Bad"]

roc_rf_A <- roc(valid_data$target, pred_rf_A)
roc_rf_B <- roc(valid_data$target, pred_rf_B)

auc(roc_rf_A)
auc(roc_rf_B)

ggroc(list(
  Logistic_A = roc_A,
  Logistic_B = roc_B,
  RandomForest_A = roc_rf_A,
  RandomForest_B = roc_rf_B
)) +
  labs(title = "Final Model Comparison: Logistic Regression vs Random Forest (Tuned)",
       x = "Specificity", y = "Sensitivity", color = "Model") +
  theme_minimal()


# =====================================================================================
# 17. FINAL COMPARISON: MODEL RISK TIERS vs LENDING CLUB GRADES
# =====================================================================================
test_data <- test_data %>%
  mutate(pred_prob = predict(model_B, newdata = test_data, type = "response"))

test_data <- test_data %>%
  mutate(model_tier = ntile(pred_prob, 7)) %>%
  mutate(model_tier = factor(model_tier, labels = c("Tier 1 (Lowest Risk)", "Tier 2", "Tier 3",
                                                    "Tier 4", "Tier 5", "Tier 6",
                                                    "Tier 7 (Highest Risk)")))

model_tier_performance <- test_data %>%
  group_by(model_tier) %>%
  summarize(
    n_loans = n(),
    actual_default_rate = mean(target) * 100
  )

print(model_tier_performance)

grade_performance <- test_data %>%
  group_by(grade) %>%
  summarize(
    n_loans = n(),
    actual_default_rate = mean(target) * 100
  ) %>%
  arrange(grade)

print(grade_performance)


# =====================================================================================
# 18. SIDE-BY-SIDE VISUAL COMPARISON
# =====================================================================================
ggplot(model_tier_performance, aes(x = model_tier, y = actual_default_rate)) +
  geom_col(fill = "#3182bd") +
  labs(title = "Actual Default Rate by RiskLens Model Tier",
       subtitle = "Independent model, built without grade/sub_grade",
       x = "Model Risk Tier", y = "Actual Default Rate (%)") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggplot(grade_performance, aes(x = grade, y = actual_default_rate, fill = grade)) +
  geom_col() +
  labs(title = "Actual Default Rate by Lending Club Grade",
       subtitle = "Lending Club's own risk assessment",
       x = "Lending Club Grade", y = "Actual Default Rate (%)") +
  theme_minimal() +
  theme(legend.position = "none")

model_tier_performance_clean <- model_tier_performance %>%
  filter(!is.na(model_tier)) %>%
  rename(segment = model_tier) %>%
  mutate(system = "RiskLens Model")

grade_performance_clean <- grade_performance %>%
  rename(segment = grade) %>%
  mutate(system = "Lending Club Grade")

combined <- bind_rows(
  model_tier_performance_clean %>% mutate(segment = as.character(segment)),
  grade_performance_clean %>% mutate(segment = as.character(segment))
)

ggplot(combined, aes(x = reorder(segment, actual_default_rate), y = actual_default_rate, fill = system)) +
  geom_col(position = "dodge") +
  facet_wrap(~system, scales = "free_x") +
  labs(title = "Risk Separation: RiskLens Model vs Lending Club Grade",
       subtitle = "Lending Club achieves wider separation between safest and riskiest segments",
       x = "Risk Segment", y = "Actual Default Rate (%)") +
  theme_minimal() +
  theme(legend.position = "none", axis.text.x = element_text(angle = 45, hjust = 1))


# =====================================================================================
# 19. EXPORT FINAL TABLES FOR DASHBOARD
# =====================================================================================
model_tier_performance_final <- model_tier_performance %>%
  filter(!is.na(model_tier))

write_csv(model_tier_performance_final, here("outputs", "model_tier_performance.csv"))
write_csv(grade_performance, here("outputs", "grade_performance.csv"))
write_csv(combined, here("outputs", "combined_risk_comparison.csv"))

test_data_export <- test_data %>%
  select(loan_amnt, term, int_rate, grade, sub_grade, annual_inc, dti, emp_length,
         home_ownership, purpose, verification_status, delinq_2yrs, inq_last_6mths,
         open_acc, pub_rec, revol_bal, revol_util, total_acc, issue_d,
         loan_status, target, pred_prob, model_tier)

write_csv(test_data_export, here("outputs", "test_predictions_detailed.csv"))

importance_A <- tibble(
  feature = names(rf_A$variable.importance),
  importance = rf_A$variable.importance
) %>% arrange(desc(importance))

importance_B <- tibble(
  feature = names(rf_B$variable.importance),
  importance = rf_B$variable.importance
) %>% arrange(desc(importance))

write_csv(importance_A, here("outputs", "feature_importance_A.csv"))
write_csv(importance_B, here("outputs", "feature_importance_B.csv"))

list.files(here("outputs"))
