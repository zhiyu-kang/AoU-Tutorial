require(pROC)
evaluate_beta <- function(beta,
                          C_tr, Z_tr, delta_tr,   # training half
                          C_te, Z_te, delta_te   # test  half
) {
  # 1) ensure Z are matrices
  Z_tr <- as.matrix(Z_tr)
  Z_te <- as.matrix(Z_te)
  
  # 2) sizes
  n_tr <- length(delta_tr)
  n_te <- length(delta_te)
  
  # 3) test‐to‐train kernel weights
  h <- sd(C_tr) / ( sum(delta_tr) )^0.25
  K_te_tr <- matrix(
    dnorm(outer(C_te, C_tr, "-") / h)/h,
    nrow = n_te, ncol = n_tr
  )
  
  # 4) estimate phi at each test point
  phi_te <- numeric(n_te)
  for (j in seq_len(n_te)) {
    w_j       <- K_te_tr[j, ]      # weights for test point j
    fit       <- glm(delta_tr ~ 1,
                     family  = binomial(),
                     weights = w_j,
                     offset  = drop(Z_tr %*% beta),
                     control = glm.control(epsilon = 1e-8, maxit = 25))
    phi_te[j] <- coef(fit)[1]
  }
  
  # 5) form test‐set linear predictor
  eta_te <- phi_te + drop(Z_te %*% beta)
  
  # 6) compute AUC
  roc_obj <- roc(delta_te, eta_te, quiet = TRUE, direction = "<")
  auc_val <- as.numeric(auc(roc_obj))
  
  # 8) return everything
  list(
    auc   = auc_val,
    eta   = eta_te,
    phi   = phi_te
  )
}

Q <- function(lp, C, delta) {
  # lp    : numeric vector of risk‐scores training based
  # C     : numeric vector of censoring / follow‐up times==testing
  # delta : 0/1 event indicators (1=event, 0=censored)
  #
  # We only compare pairs (i,j) with delta[i]==1, delta[j]==0, and C[i]<C[j].
  # Then we count how often lp[i]>lp[j] among those pairs.
  
  # identify cases and controls
  cases    <- which(delta == 1)
  controls <- which(delta == 0)
  
  # if there are no comparable pairs, return NA
  if (length(cases)==0 || length(controls)==0) return(NA_real_)
  
  # build boolean matrices of size length(cases) × length(controls)
  #   compare time:  Ci < Cj
  time_cmp <- outer(C[cases], C[controls], `<`)
  #   compare score: lp_i > lp_j
  score_cmp <- outer(lp[cases], lp[controls], `>`)
  
  # total comparable pairs
  total_pairs <- sum(time_cmp)
  # concordant = both Ci<Cj and lp_i>lp_j
  conc_pairs  <- sum(time_cmp & score_cmp)
  
  conc_pairs / total_pairs
}