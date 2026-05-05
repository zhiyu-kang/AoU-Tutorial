# Example workflow: all-population initial/SSL models and Black score-adjusted models
# Switch to Block code if parallel inside function explode
rm(list = ls())
#change it to your version name
version <- "V5_pseudo_Showcase"

# ==============================================================================
# 0. Setup
# ==============================================================================

source.dir <- "~/shared/Source/"
shared.dir <- "~/shared/shared/"
proj.dir   <- "~/shared/project/"

source(paste0(shared.dir, "source_all_functions.R"))

set.seed(2025)

# Required objects assumed to be available after source/data loading:
# x         : full analysis data frame
# SNP       : character vector of all-population SNP names
# SNP_black : character vector of Black-specific SNP names (You will need extra SNP Data)
# ==============================================================================
# 1. Split survey-labeled participants into train/test
# ==============================================================================

survey_rows <- which(!is.na(x$delta) & !is.na(x$C_survey))

test_rows <- sample(
  survey_rows,
  size = floor(0.3 * length(survey_rows))
)

x_test  <- x[test_rows, , drop = FALSE]
x_train <- x[-test_rows, , drop = FALSE]

x_train_black <- x_train[
  x_train$race == "Black or African American",
  ,
  drop = FALSE
]

x_test_black <- x_test[
  x_test$race == "Black or African American",
  ,
  drop = FALSE
]

# ==============================================================================
# 2. Fit all-population initial and Evaluation
# ==============================================================================

fit_init_all <- train_init(
  delta = x_train$delta,
  C     = x_train$C_survey,
  Z     = x_train[, SNP, drop = FALSE],
  cache = make_cache(proj.dir, "fit_init_all_cache", version)
)

AUC_init_all <- auc_survey(
  fit_beta = fit_init_all,
  delta    = x_test$delta,
  C        = x_test$C_survey,
  Z        = x_test[, SNP, drop = FALSE],
  B_test   = 100,
  n_cores  = 3,
  cache    = make_cache(proj.dir, "auc_init_all_checkpoint", version)
)

Cindex_init_all <- concordance_survey(
  fit_beta = fit_init_all,
  delta    = x_test$delta,
  C        = x_test$C_survey,
  Z        = x_test[, SNP, drop = FALSE],
  n_cores  = 3
)
betadelta_all <- fit_init_all$beta


# ==============================================================================
# 3. Fit all-population SSL models and evaluation
# ==============================================================================

fit_ssl_all <- train_ssl(
  DELTA    = x_train$DELTA,
  C        = x_train$C_ehr,
  X        = x_train$X,
  Z        = x_train[, SNP, drop = FALSE],
  fit_init = fit_init_all,
  cache    = make_cache(proj.dir, "fit_ssl_all_cache", version)
)

AUC_ssl_all <- auc_survey(
  fit_beta = fit_ssl_all,
  delta    = x_test$delta,
  C        = x_test$C_survey,
  Z        = x_test[, SNP, drop = FALSE],
  B_test   = 100,
  n_cores  = 3,
  cache    = make_cache(proj.dir, "auc_ssl_all_checkpoint", version)
)

Cindex_ssl_all <- concordance_survey(
  fit_beta = fit_ssl_all,
  delta    = x_test$delta,
  C        = x_test$C_survey,
  Z        = x_test[, SNP, drop = FALSE],
  n_cores  = 3
)

betaSSL_all <- fit_ssl_all$beta

# ==============================================================================
# 4. Construct all-population initial SNP score for Black participants
# ==============================================================================
x_train_black$snpscore_init <- drop(
  as.matrix(x_train_black[, SNP, drop = FALSE]) %*% betadelta_all
)

x_test_black$snpscore_init <- drop(
  as.matrix(x_test_black[, SNP, drop = FALSE]) %*% betadelta_all
)

SNP_black_score_init <- c(SNP_black, "snpscore_init")

# ==============================================================================
# 5. Fit Black initial-score adjusted initial model
# ==============================================================================
fit_init_black_score_init <- train_init(
  delta = x_train_black$delta,
  C     = x_train_black$C_survey,
  Z     = x_train_black[, SNP_black_score_init, drop = FALSE],
  cache = make_cache(proj.dir, "fit_init_black_score_init_cache", version)
)

AUC_black_score_init <- auc_survey(
  fit_beta = fit_init_black_score_init,
  delta    = x_test_black$delta,
  C        = x_test_black$C_survey,
  Z        = x_test_black[, SNP_black_score_init, drop = FALSE],
  B_test   = 100,
  n_cores  = 3,
  cache    = make_cache(proj.dir, "auc_black_score_init_checkpoint", version)
)

Cindex_black_score_init <- concordance_survey(
  fit_beta = fit_init_black_score_init,
  delta    = x_test_black$delta,
  C        = x_test_black$C_survey,
  Z        = x_test_black[, SNP_black_score_init, drop = FALSE],
  n_cores  = 3
)
# ==============================================================================
# 6. Construct all-population SSL SNP score for Black participants
# ==============================================================================

x_train_black$snpscore_SSL <- drop(
  as.matrix(x_train_black[, SNP, drop = FALSE]) %*% betaSSL_all
)

x_test_black$snpscore_SSL <- drop(
  as.matrix(x_test_black[, SNP, drop = FALSE]) %*% betaSSL_all
)

# Final Black adjusted covariate space:
# 10 Black-specific SNPs + all-population SSL score
SNP_black_score_SSL <- c(SNP_black, "snpscore_SSL")

# ==============================================================================
# 7. Fit Black SSL-score adjusted initial model
# ==============================================================================

fit_init_black_score_SSL <- train_init(
  delta = x_train_black$delta,
  C     = x_train_black$C_survey,
  Z     = x_train_black[, SNP_black_score_SSL, drop = FALSE],
  cache = make_cache(proj.dir, "fit_init_black_score_ssl_cache", version)
)

# ==============================================================================
# 8. Fit Black SSL-score adjusted SSL model
# ==============================================================================

fit_ssl_black_score <- train_ssl(
  DELTA    = x_train_black$DELTA,
  C        = x_train_black$C_ehr,
  X        = x_train_black$X,
  Z        = x_train_black[, SNP_black_score_SSL, drop = FALSE],
  fit_init = fit_init_black_score_SSL,
  cache    = make_cache(proj.dir, "fit_ssl_black_score_cache", version)
)

# ==============================================================================
# 9. Evaluate AUC and C-index uncertainty on Black test set
# ==============================================================================

AUC_black_score_SSL <- auc_survey(
  fit_beta = fit_ssl_black_score,
  delta    = x_test_black$delta,
  C        = x_test_black$C_survey,
  Z        = x_test_black[, SNP_black_score_SSL, drop = FALSE],
  B_test   = 100,
  n_cores  = 3,
  cache    = make_cache(proj.dir, "auc_black_score_SSL_checkpoint", version)
)

Cindex_black_score_SSL <- concordance_survey(
  fit_beta = fit_ssl_black_score,
  delta    = x_test_black$delta,
  C        = x_test_black$C_survey,
  Z        = x_test_black[, SNP_black_score_SSL, drop = FALSE],
  n_cores  = 3
)

# ==============================================================================
# 10. Save results
# ==============================================================================

save(
  fit_init_all,
  fit_ssl_all,
  fit_init_black_score_init,
  fit_init_black_score_SSL,
  fit_ssl_black_score,
  AUC_init_all,
  Cindex_init_all,
  AUC_ssl_all,
  Cindex_ssl_all,
  AUC_black_score_init,
  Cindex_black_score_init,
  AUC_black_score_SSL,
  Cindex_black_score_SSL,
  SNP_black_score_init,
  SNP_black_score_SSL,
  version,
  file = make_cache(proj.dir, "black_adjusted_full_results", version)
)
print(AUC_init_all)
print(Cindex_init_all)

print(AUC_ssl_all)
print(Cindex_ssl_all)

print(AUC_black_score_init)
print(Cindex_black_score_init)

print(AUC_black_score_SSL)
print(Cindex_black_score_SSL)