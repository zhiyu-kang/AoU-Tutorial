version <- "V5_Commorbities_Showcase"

#===============================================================================
# Directories & setup
#===============================================================================
source.dir <- "~/shared/Source/"
shared.dir <- "~/shared/shared/"
proj.dir   <- "~/shared/project/"

source(paste0(shared.dir, "utility.R"))
source(paste0(shared.dir, "parallel.R"))# defines: np, cl, registerDoParallel, doRNG
source(paste0(shared.dir, "Evaluation.R"))
source(paste0(shared.dir, "beta_delta.R"))
source(paste0(shared.dir, "beta_delta_perturb.R"))
source(paste0(shared.dir, "Sk_sym_perturb.R"))
source(paste0(shared.dir, "Sk_sym.R"))
source(paste0(shared.dir, "W_hat_adaPCA.R"))
source(paste0(shared.dir, "W_hat_PCA.R"))
source(paste0(shared.dir, "data_io.R"))
source(paste0(shared.dir, "Reader Function.R"))
pak.list <- c("glmnet","foreach","doParallel","doRNG","pROC")
load.packlist(pak.list)

init.cache <- make_cache(proj.dir, "fit_init", version)
ssl.cache  <- make_cache(proj.dir, "fit_ssl",  version)

SNP <- c(
  "12:111446804:T:C", "12:45976333:C:G", "13:39781776:T:C",
  "14:104920174:G:A", "14:68287978:G:A", "1:116738074:C:T",
  "5:143224856:A:G",  "6:159082054:A:G", "6:36414159:G:GA",
  "9:34710263:G:A"
)

x_survey <- x[complete.cases(x[, c("C_survey", "delta", SNP)]), ]
set.seed(2025)
train_id <- sample(seq_len(nrow(x_survey)), floor(0.7 * nrow(x_survey)))
x_train <- x_survey[train_id, ]
x_test  <- x_survey[-train_id, ]
x_test_black<-x_test[x_test$race=="Black or African American",,drop=FALSE]

fit_init <- train_init(
  delta       = x_train$delta,
  C           = x_train$C_survey,
  Z           = x_train[, SNP],
  cache       = init.cache,
  Nperturb    = 1000L,
  n_unlabeled = nrow(x_train),
  batch_size  = 20L,
  n_cores     = 1L,
  seed        = 531L
)

fit_ssl <- train_ssl(
  DELTA      = x_train$DELTA,
  C          = x_train$C_ehr,
  X          = x_train$X,
  Z          = x_train[, SNP],
  fit_init   = fit_init,
  cache      = ssl.cache,
  batch_size = 20L,
  n_cores    = 1L
)

betaSSL_all <- fit_ssl$beta