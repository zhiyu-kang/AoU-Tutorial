rm(list = objects())
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

# Files
glm.file   <- file.backlog2(proj.dir, "ALL_GLM_",   "rda", version)
delta.file <- file.backlog2(proj.dir, "ALL_DELTA_", "rda", version)
ssl.file   <- file.backlog2(proj.dir, "ALL_SSL_",   "rda", version)           # final betaSSL + timings
ssl.ckpt   <- file.backlog2(proj.dir, "ALL_SSL_CKPT_", "rda", version)        # batch checkpoint

# ---- Rebuild old-style containers expected by your pipeline ----
label_split_all <- list(
  train = list(
    labeled_data = labeled_tr,
    Z            = Z_labeled_tr,
    race         = race_labeled_tr,
    id           = id_labeled_tr,
    V            = V_labeled_tr
  ),
  test = list(
    labeled_data = labeled_te,
    Z            = Z_labeled_te,
    race         = race_labeled_te,
    id           = id_labeled_te,
    V            = V_labeled_te
  )
)

# Your old code uses unlabeled_all in "Parameters" section
unlabeled_all <- unlabeled_tr
Z_unlabeled_mat_all <- Z_unlabeled_tr
race_unlabeled_all <- race_unlabeled_tr
id_unlabeled_all <- id_unlabeled_tr
V_unlabeled_all <- V_unlabeled_tr


#===============================================================================
# 1) Supervised baseline (Weighted GLM)  ---------------------------------------
#   - Train: ALL labeled training (weighted)
#   - Test : Black labeled testing
#===============================================================================
if (file.exists(glm.file)) {
  load(glm.file)  # loads: beta_glm_all_w, auc_all_glm_w, concord_beta_all_GLM_w, T_all_GLM_w
} else {
  
  # ---- Training inputs (ALL labeled training) ----
  Z_tr     <- label_split_all$train$Z
  delta_tr <- label_split_all$train$labeled_data$delta
  C_tr     <- label_split_all$train$labeled_data$C
  V_tr     <- label_split_all$train$V
  
  stopifnot(length(delta_tr) == nrow(Z_tr),
            length(C_tr)     == nrow(Z_tr),
            length(V_tr)     == nrow(Z_tr),
            all(is.finite(V_tr)),
            all(V_tr > 0))
  
  # ---- Testing inputs (Black labeled test) ----
  Z_te     <- label_split_black$test$Z
  delta_te <- label_split_black$test$labeled_data$delta
  C_te     <- label_split_black$test$labeled_data$C
  
  stopifnot(length(delta_te) == nrow(Z_te),
            length(C_te)     == nrow(Z_te))
  
  # ---- Fit weighted GLM ----
  T_all_GLM_w <- tictoc({
    fit_tr_glm_w <- glm.fit(
      x       = Z_tr,
      y       = delta_tr,
      family  = binomial(),
      weights = V_tr
    )
    beta_glm_all_w <- coef(fit_tr_glm_w)
  })
  
  # ---- Evaluate (same functions you used before) ----
  auc_all_glm_w <- evaluate_beta(
    beta     = beta_glm_all_w,
    C_tr     = C_tr, Z_tr = Z_tr, delta_tr = delta_tr,
    C_te     = C_te, Z_te = Z_te, delta_te = delta_te
  )
  
  lp_beta_all_GLM_w <- drop(Z_te %*% beta_glm_all_w)
  concord_beta_all_GLM_w <- Q(lp_beta_all_GLM_w, C = C_te, delta = delta_te)
  
  # ---- Save ----
  save(beta_glm_all_w, auc_all_glm_w, concord_beta_all_GLM_w, T_all_GLM_w,
       file = glm.file)
  
  message(sprintf("[GLM-W] done in %.2fs", T_all_GLM_w["elapsed"]))
}


#===============================================================================
# 2) Δ-init: bandwidth, kernel, init beta (weights ONLY inside init.beta.perturb)
#===============================================================================
if (file.exists(delta.file)) {
  load(delta.file)  # loads: h_all, KC_all, betadelta_all_w, T_all_delta
} else {
  
  # ---- Training inputs ----
  C_tr     <- label_split_all$train$labeled_data$C
  delta_tr <- label_split_all$train$labeled_data$delta
  Z_tr     <- label_split_all$train$Z
  V_tr     <- label_split_all$train$V
  
  stopifnot(length(C_tr)     == length(delta_tr),
            length(delta_tr) == nrow(Z_tr),
            length(V_tr)     == nrow(Z_tr),
            all(is.finite(V_tr)),
            all(V_tr > 0))
  
  T_all_delta <- tictoc({
    
    # (1) SAME bandwidth as old code (unweighted)
    h_all <- sd(C_tr) / (sum(delta_tr))^0.25
    
    # (2) SAME kernel as old code (unweighted)
    KC_all <- dnorm(
      as.matrix(dist(C_tr / h_all, diag = TRUE, upper = TRUE))
    ) / h_all
    
    # (3) Weighted init beta (weights applied inside init.beta.perturb)
    betadelta_all_w <- init.beta.perturb(
      delta = delta_tr,
      Z     = Z_tr,
      KC    = KC_all,
      V     = V_tr,
      init  = rep(0, ncol(Z_tr)),
      tol   = 1e-7,
      maxit = 100
    )
  })
  
  auc_all_betadelta_w <- evaluate_beta(
    beta     = betadelta_all_w,
    C_tr     = C_tr, Z_tr = Z_tr, delta_tr = delta_tr,
    C_te     = label_split_black$test$labeled_data$C,
    Z_te     = label_split_black$test$Z,
    delta_te = label_split_black$test$labeled_data$delta
  )
  
  lp_beta_all_delta_w <- drop(label_split_black$test$Z %*% betadelta_all_w)
  concord_beta_all_delta_w <- Q(lp_beta_all_delta_w,
                                C = label_split_black$test$labeled_data$C,
                                delta = label_split_black$test$labeled_data$delta)
  
  save(h_all, KC_all,
       auc_all_betadelta_w, concord_beta_all_delta_w,
       betadelta_all_w, T_all_delta,
       file = delta.file)
  
  message(sprintf("[DELTA-W-init] done in %.2fs", T_all_delta["elapsed"]))
}




