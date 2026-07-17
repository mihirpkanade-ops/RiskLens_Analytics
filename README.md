# RiskLens Analytics: Credit Default Risk Modeling & Portfolio Intelligence Dashboard

Independent credit risk model built on Lending Club's public loan data, benchmarked
against Lending Club's own A–G grading system across 635,679 historical loans.

---

## The Problem

Lending Club assigns every loan a letter grade (A–G) as its own estimate of default
risk. The central question: can a model built independently, without any knowledge
of Lending Club's grades, separate risky loans from safe ones just as well as
Lending Club's own system does?

---

## Dataset

One public dataset from Kaggle, cleaned and split by time:

| Stage | Rows | Notes |
|---|---|---|
| Raw import | 2,260,701 | All accepted loans, 2007–2018Q4 |
| After cleaning | 635,679 | Missing values dropped, immature loans excluded, target defined |
| Train set | 446,731 | Earliest ~70% of loans by issue date |
| Validation set | 106,717 | Next ~15% by issue date |
| Test set | 82,231 | Most recent ~15% by issue date |

Overall default rate in the modeled dataset: **14.46%** bad (Charged Off / Default /
Late 31-120 days) vs. **85.54%** good (Fully Paid).

Source: [Kaggle - Lending Club Loan Data](https://www.kaggle.com/datasets/wordsforthewise/lending-club) - not included in this repo due to file size (~2GB); see [How to Run](#how-to-run).

---

## Tools

- **Language:** R
- **Libraries:** tidyverse, here, broom, car, scales, pROC, ranger
- **Methods:** Logistic regression, random forest, ROC/AUC evaluation, time-based train/validation/test split

---

## Key Findings

**Lending Club's own grading separates risk more widely than the RiskLens model.**
Grade A loans default at ~5%, climbing to ~56% for Grade G. The RiskLens model's 7
risk tiers span a narrower range, from roughly 4% to 29%. Both systems rank risk in
the correct direction, but Lending Club's grading resolves more of it.

**Including `int_rate` clearly improves the model.**
Model B (logistic regression with `int_rate`) reaches a validation AUC of **0.6883**,
versus **0.6416** for Model A (without `int_rate`) - a meaningful gap. The same
pattern holds for random forest: 0.6779 with `int_rate` vs. 0.6401 without.

**Logistic regression outperformed random forest here.**
Both logistic models beat their random forest counterparts on validation AUC
(0.6883 vs. 0.6779 for the `int_rate`-included versions; 0.6416 vs. 0.6401 without).
Model B (logistic regression) was selected as the final model.

**Excluding `int_rate` costs real predictive power.**
Interest rate is *set* partly using Lending Club's own grade, so leaving it out was
meant to keep the model independent. But the AUC gap between Model A and Model B
shows that choice comes at a real cost - `int_rate` carries market-priced risk
signal that goes beyond just encoding Lending Club's grade.

**Time-based splitting, not random.**
Loans were split into train/validation/test by issue date (70th/85th percentile
cutoffs), so the model is validated and tested only on loans issued after its
training window - closer to how the model would actually be deployed.

---

## Model Comparison

All four models trained/evaluated on the same time-based split. AUC measured on the validation set (106,717 loans).

| Model | Features | Validation AUC |
|---|---|---|
| Logistic Regression A | Excludes `int_rate` | 0.6416 |
| **Logistic Regression B** | **Includes `int_rate`** | **0.6883** |
| Random Forest A (tuned, mtry=3) | Excludes `int_rate` | 0.6401 |
| Random Forest B (tuned, mtry=3) | Includes `int_rate` | 0.6779 |

**Logistic Regression B** was selected as the final model, based on the strongest validation AUC. It was used to generate predicted default probabilities and risk tiers on the held-out test set (82,231 loans).

---

## Risk Tiering

Test-set loans were split into 7 equal-sized tiers using Model B's predicted default
probability (`ntile`), Tier 1 = lowest risk, Tier 7 = highest. Actual observed default
rates per tier were then compared directly against Lending Club's grade-level default
rates on the same test set - this comparison is the centerpiece of the dashboard.

---

## How to Run

1. Download `accepted_2007_to_2018Q4.csv.gz` from [Kaggle](https://www.kaggle.com/datasets/wordsforthewise/lending-club), unzip it, and place it in the project root
2. Open `RiskLens.Rproj` in RStudio - sets the working directory via `here()`
3. Install packages if needed:
   ```r
   install.packages(c("tidyverse", "here", "broom", "car", "scales", "pROC", "ranger"))
   ```
4. Run `RiskLens.R`

---

## Project Structure

```
RiskLens_Analytics/
│
├── RiskLens.R                          # Full analysis script: cleaning → modeling → export
├── RiskLens.Rproj                      # RStudio project file (sets working directory)
├── outputs/                            # Exported summary tables (Tableau data sources)
│   ├── grade_count.csv                 # Loan counts by Lending Club grade
│   ├── subgrade_count.csv              # Loan counts by Lending Club sub-grade
│   ├── grade_performance.csv           # Actual default rate by grade (test set)
│   ├── model_tier_performance.csv      # Actual default rate by RiskLens model tier (test set)
│   ├── combined_risk_comparison.csv    # Combined grade + tier comparison (centerpiece chart)
│   ├── feature_importance_A.csv        # Random forest variable importance (Model A features)
│   ├── feature_importance_B.csv        # Random forest variable importance (Model B features)
│   └── test_predictions_detailed.csv   # Row-level test set predictions (drill-down dashboard)
├── .gitignore
└── README.md
```

Note: `outputs/loan_model_data.csv` is generated by the script but excluded from
this repo (~76MB). It powers the "Loan Volume Over Time" and "Target Variable
Distribution" dashboard sheets - regenerate it by running `RiskLens.R` before
opening those two sheets.

---

## Full Portfolio

Live interactive dashboard (4 pages: Portfolio Overview, Target & Risk
Segmentation, RiskLens Model vs. Lending Club, Portfolio Drill-Down):
**[Tableau Public](https://public.tableau.com/app/profile/mihir.kanade/viz/RiskLensAnalytics/PortfolioOverview)**
