#-------------------------------------------------------------------------------
# Black inputs from NEW CSV files (V13_alt)
#-------------------------------------------------------------------------------
version <- "V13_alt"
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

pak.list <- c("glmnet","foreach","doParallel","doRNG","pROC")
load.packlist(pak.list)

# Time Helpers
tictoc <- function(expr) system.time(eval.parent(substitute({expr})))

#===============================================================================
# Data  
#===============================================================================
prepared_rda<-file.path(proj.dir, paste0("case_control_alt_", version, ".RData"))
load(prepared_rda)

black_tr_lab_file <- file.path(proj.dir,
                               paste0("RA_Black_TRAIN_LABELED_oldCov_oldSNP_plusNew10_", version, ".csv")
)
black_te_lab_file <- file.path(proj.dir,
                               paste0("RA_Black_TEST_LABELED_oldCov_oldSNP_plusNew10_", version, ".csv")
)
black_tr_unlab_file <- file.path(proj.dir,
                                 paste0("RA_Black_TRAIN_UNLABELED_oldCov_oldSNP_plusNew10_", version, ".csv")
)

stopifnot(file.exists(black_tr_lab_file))
stopifnot(file.exists(black_te_lab_file))
stopifnot(file.exists(black_tr_unlab_file))

Black_TR_LAB   <- readr::read_csv(black_tr_lab_file, show_col_types = FALSE)
Black_TE_LAB   <- readr::read_csv(black_te_lab_file, show_col_types = FALSE)
Black_TR_UNLAB <- readr::read_csv(black_tr_unlab_file, show_col_types = FALSE)

cat("[INFO] Read CSVs:\n",
    "   TR_LAB rows:   ", nrow(Black_TR_LAB), "\n",
    "   TE_LAB rows:   ", nrow(Black_TE_LAB), "\n",
    "   TR_UNLAB rows: ", nrow(Black_TR_UNLAB), "\n", sep = "")

#===============================================================================
# Define the 10 NEW SNPs (these are the ones you selected)
#   (Use your actual top10 list here; example placeholder below)
#===============================================================================
Black_new10_snps <- c(
  "8:128564231:T:C",
  "18:3542249:T:C",
  "18:12880207:A:G",
  "19:35722170:A:G",
  "4:48218822:G:A",
  "1:2552522:G:A",
  "5:134503843:C:T",
  "15:69699078:G:A",
  "11:2301990:G:A"
)

stopifnot(all(Black_new10_snps %in% names(Black_TR_LAB)))
stopifnot(all(Black_new10_snps %in% names(Black_TE_LAB)))
stopifnot(all(Black_new10_snps %in% names(Black_TR_UNLAB)))

#===============================================================================
# Align with existing IDs from your loaded .rda objects
#   You should already have:
#     - label_split_black$train$id, label_split_black$test$id
#     - id_black_unlab (or unlab_split_black$train$id)
#===============================================================================

id_black_tr <- as.character(label_split_black$train$id)
id_black_te <- as.character(label_split_black$test$id)

# unlabeled train ids:
if (exists("id_black_unlab")) {
  id_black_unlab <- as.character(id_black_unlab)
} else if (exists("unlab_split_black")) {
  id_black_unlab <- as.character(unlab_split_black$train$id)
} else {
  stop("No unlabeled Black IDs found: need id_black_unlab or unlab_split_black$train$id.")
}

#===============================================================================
# Match rows by person_id (same style as before)
#===============================================================================
idx_tr    <- match(id_black_tr,    as.character(Black_TR_LAB$person_id))
idx_te    <- match(id_black_te,    as.character(Black_TE_LAB$person_id))
idx_unlab <- match(id_black_unlab, as.character(Black_TR_UNLAB$person_id))

cat("[INFO] ID matching NA counts:\n",
    "   TR_LAB missing:   ", sum(is.na(idx_tr)), "\n",
    "   TE_LAB missing:   ", sum(is.na(idx_te)), "\n",
    "   TR_UNLAB missing: ", sum(is.na(idx_unlab)), "\n", sep = "")

# If any IDs not found, drop them consistently from split objects
keep_id_tr <- !is.na(idx_tr)
keep_id_te <- !is.na(idx_te)
keep_id_un <- !is.na(idx_unlab)

if (any(!keep_id_tr)) {
  label_split_black$train$Z            <- label_split_black$train$Z[keep_id_tr, , drop = FALSE]
  label_split_black$train$labeled_data <- label_split_black$train$labeled_data[keep_id_tr, , drop = FALSE]
  label_split_black$train$id           <- label_split_black$train$id[keep_id_tr]
  id_black_tr <- id_black_tr[keep_id_tr]
  idx_tr <- idx_tr[keep_id_tr]
}

if (any(!keep_id_te)) {
  label_split_black$test$Z            <- label_split_black$test$Z[keep_id_te, , drop = FALSE]
  label_split_black$test$labeled_data <- label_split_black$test$labeled_data[keep_id_te, , drop = FALSE]
  label_split_black$test$id           <- label_split_black$test$id[keep_id_te]
  id_black_te <- id_black_te[keep_id_te]
  idx_te <- idx_te[keep_id_te]
}

if (any(!keep_id_un)) {
  # unlabeled objects: these names depend on your earlier saved .rda; keep same style
  id_black_unlab <- id_black_unlab[keep_id_un]
  idx_unlab <- idx_unlab[keep_id_un]
  
  if (exists("Z_unlabeled_mat_black")) Z_unlabeled_mat_black <- Z_unlabeled_mat_black[keep_id_un, , drop = FALSE]
  if (exists("unlabeled.black"))       unlabeled.black       <- unlabeled.black[keep_id_un, , drop = FALSE]
}

#===============================================================================
# Build Z matrices for NEW SNPs (call them Z_black_*_other like before)
#===============================================================================
Z_black_tr_other <- as.matrix(Black_TR_LAB[idx_tr, Black_new10_snps, drop = FALSE])
Z_black_te_other <- as.matrix(Black_TE_LAB[idx_te, Black_new10_snps, drop = FALSE])
Z_black_unlabel_other <- as.matrix(Black_TR_UNLAB[idx_unlab, Black_new10_snps, drop = FALSE])

storage.mode(Z_black_tr_other) <- "numeric"
storage.mode(Z_black_te_other) <- "numeric"
storage.mode(Z_black_unlabel_other) <- "numeric"

#===============================================================================
# Complete-case filtering (FINAL, before any model training)
#   Goal: after this block, NO NA in:
#     - labeled train/test: delta, C, V, old Z, new Z
#     - unlabeled train:   DELTA, C, V, old Z, new Z (if used)
#===============================================================================

#-------------------------
# Labeled TRAIN
#-------------------------
keep_tr_cc <- complete.cases(
  Z_black_tr_other,
  label_split_black$train$Z,
  label_split_black$train$labeled_data$delta,
  label_split_black$train$labeled_data$C,
  label_split_black$train$V
) & (label_split_black$train$V > 0)

cat("[INFO] Drop TR_LAB (NA in newZ/oldZ/delta/C/V or V<=0): ",
    sum(!keep_tr_cc), "\n", sep="")

Z_black_tr_other <- Z_black_tr_other[keep_tr_cc, , drop=FALSE]
label_split_black$train$Z            <- label_split_black$train$Z[keep_tr_cc, , drop=FALSE]
label_split_black$train$labeled_data <- label_split_black$train$labeled_data[keep_tr_cc, , drop=FALSE]
label_split_black$train$V            <- label_split_black$train$V[keep_tr_cc]
label_split_black$train$id           <- label_split_black$train$id[keep_tr_cc]
id_black_tr                           <- id_black_tr[keep_tr_cc]

#-------------------------
# Labeled TEST
#-------------------------
keep_te_cc <- complete.cases(
  Z_black_te_other,
  label_split_black$test$Z,
  label_split_black$test$labeled_data$delta,
  label_split_black$test$labeled_data$C
  # label_split_black$test$V exists but should be 1’s; include if you want:
  # , label_split_black$test$V
)

cat("[INFO] Drop TE_LAB (NA in newZ/oldZ/delta/C): ",
    sum(!keep_te_cc), "\n", sep="")

Z_black_te_other <- Z_black_te_other[keep_te_cc, , drop=FALSE]
label_split_black$test$Z            <- label_split_black$test$Z[keep_te_cc, , drop=FALSE]
label_split_black$test$labeled_data <- label_split_black$test$labeled_data[keep_te_cc, , drop=FALSE]
label_split_black$test$id           <- label_split_black$test$id[keep_te_cc]
if (!is.null(label_split_black$test$V)) label_split_black$test$V <- label_split_black$test$V[keep_te_cc]
id_black_te                          <- id_black_te[keep_te_cc]

#-------------------------
# Unlabeled TRAIN
#-------------------------
# (depending on your object names; you have Z_black_unlabel_other already)
keep_un_cc <- complete.cases(
  Z_black_unlabel_other
  # if you also need to enforce no NA in old unlabeled Z / weights / outcomes, add them here:
  # , unlab_split_black$train$Z
  # , unlab_split_black$train$unlabeled_data$DELTA
  # , unlab_split_black$train$unlabeled_data$C
  # , unlab_split_black$train$V
) 

cat("[INFO] Drop TR_UNLAB (NA in newZ): ",
    sum(!keep_un_cc), "\n", sep="")

Z_black_unlabel_other <- Z_black_unlabel_other[keep_un_cc, , drop=FALSE]
id_black_unlab        <- id_black_unlab[keep_un_cc]

if (exists("Z_unlabeled_mat_black")) Z_unlabeled_mat_black <- Z_unlabeled_mat_black[keep_un_cc, , drop = FALSE]
if (exists("unlabeled.black"))       unlabeled.black       <- unlabeled.black[keep_un_cc, , drop = FALSE]

cat("[INFO] Final dims after CC filtering:\n",
    "   TR_LAB: ", nrow(label_split_black$train$labeled_data), "\n",
    "   TE_LAB: ", nrow(label_split_black$test$labeled_data), "\n",
    "   TR_UNL: ", nrow(Z_black_unlabel_other), "\n",
    sep="")

# Files
glm.file   <- file.backlog2(proj.dir, "Black_GLM_",   "rda", version)
delta.file <- file.backlog2(proj.dir, "Black_DELTA_", "rda", version)
ssl.file   <- file.backlog2(proj.dir, "Black_SSL_",   "rda", version)           # final betaSSL + timings
ssl.ckpt   <- file.backlog2(proj.dir, "Black_SSL_CKPT_", "rda", version)        # batch checkpoint


#===============================================================================
# Parameters
#===============================================================================
if (!exists("Nperturb")) Nperturb <- 1000L
p <- ncol(label_split_black$train$Z)
nL_tr   <- nrow(label_split_black$train$labeled_data)
nU      <- nrow(Z_black_unlabel_other)
n_black   <- nL_tr + nU

#===============================================================================
# 1) Supervised baseline (Weighted GLM, Black score model)
#   Assumes: complete-case filtering has already been done upstream
#===============================================================================
if (file.exists(glm.file)) {
  load(glm.file)  # loads: beta_glm_blackscore_w, auc_black_glmscore, concord_beta_black_glm_score
} else {
  
  # old-score feature from ALL-model (no intercept, consistent with your pipeline)
  score_tr <- drop(label_split_black$train$Z %*% beta_glm_all_w)
  score_te <- drop(label_split_black$test$Z  %*% beta_glm_all_w)
  
  # design matrices = (new SNPs) + (old-score)
  Z_tr <- cbind(Z_black_tr_other, score_tr)
  Z_te <- cbind(Z_black_te_other, score_te)
  
  y_tr <- label_split_black$train$labeled_data$delta
  w_tr <- label_split_black$train$V
  
  # fit weighted logistic regression (glm.fit includes intercept automatically)
  fit <- glm.fit(
    x       = Z_tr,
    y       = y_tr,
    family  = binomial(),
    weights = w_tr
  )
  beta_glm_blackscore_w <- coef(fit)
  
  # evaluate
  auc_black_glmscore <- evaluate_beta(
    beta     = beta_glm_blackscore_w,
    C_tr     = label_split_black$train$labeled_data$C,
    Z_tr     = Z_tr,
    delta_tr = y_tr,
    C_te     = label_split_black$test$labeled_data$C,
    Z_te     = Z_te,
    delta_te = label_split_black$test$labeled_data$delta
  )
  
  lp_te <- drop(Z_te %*% beta_glm_blackscore_w)
  concord_beta_black_glm_score <- Q(
    lp_te,
    C     = label_split_black$test$labeled_data$C,
    delta = label_split_black$test$labeled_data$delta
  )
  
  save(beta_glm_blackscore_w, auc_black_glmscore, concord_beta_black_glm_score, file = glm.file)
  cat("[INFO] Saved weighted Black GLM to: ", glm.file, "\n", sep = "")
}

#===============================================================================
# 2) Δ-init: bandwidth, kernel, init beta (WEIGHTED via init.beta.perturb)
#===============================================================================
if (file.exists(delta.file)) {
  load(delta.file)  # expect: h_black, KC_black, betadelta_black_score, auc_black_betadelta_score, concord_beta_black_delta_score
} else {
  
  # ---- old-score feature from ALL Δ-init (no intercept, consistent with your pipeline) ----
  score_tr <- drop(label_split_black$train$Z %*% betadelta_all_w)
  score_te <- drop(label_split_black$test$Z  %*% betadelta_all_w)
  
  # ---- design matrices = (new SNPs) + (old-score) ----
  Z_tr <- cbind(Z_black_tr_other, score_tr)
  Z_te <- cbind(Z_black_te_other, score_te)
  
  # ---- training vectors ----
  C_tr <- label_split_black$train$labeled_data$C
  y_tr <- label_split_black$train$labeled_data$delta
  V_tr <- label_split_black$train$V
  
  # ---- bandwidth + kernel matrix (same formula as before) ----
  h_black <- sd(C_tr) / (sum(y_tr))^0.25
  
  KC_black <- dnorm(
    as.matrix(dist(C_tr / h_black, diag = TRUE, upper = TRUE))
  ) / h_black
  
  # ---- weighted init beta (weights handled inside) ----
  betadelta_black_score <- init.beta.perturb(
    delta = y_tr,
    Z     = Z_tr,
    KC    = KC_black,
    V     = V_tr
  )
  
  # ---- evaluate ----
  auc_black_betadelta_score <- evaluate_beta(
    beta     = betadelta_black_score,
    C_tr     = C_tr, Z_tr = Z_tr, delta_tr = y_tr,
    C_te     = label_split_black$test$labeled_data$C,
    Z_te     = Z_te,
    delta_te = label_split_black$test$labeled_data$delta
  )
  
  lp_te <- drop(Z_te %*% betadelta_black_score)
  concord_beta_black_delta_score <- Q(
    lp_te,
    C     = label_split_black$test$labeled_data$C,
    delta = label_split_black$test$labeled_data$delta
  )
  
  save(h_black, KC_black, betadelta_black_score,
       auc_black_betadelta_score, concord_beta_black_delta_score,
       file = delta.file)
  
  cat("[INFO] Saved weighted Black DELTA-init to: ", delta.file, "\n", sep = "")
}




