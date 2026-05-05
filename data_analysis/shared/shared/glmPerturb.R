# GLM outer-layer perturbation on all-population training
make_glm_perturb_train <- function(Z_tr = label_split_all$train$Z,
                                   y_tr = label_split_all$train$labeled_data$delta,
                                   B_train, seed = 11) {
  set.seed(seed)
  
  n_tr <- nrow(Z_tr)
  p <- ncol(Z_tr)
  
  beta_glm_pert <- matrix(NA_real_, nrow = p, ncol = B_train)
  
  for (b in seq_len(B_train)) {
    V_b <- rbeta(n_tr, 0.5, 1.5) * 4
    
    fit_b <- glm.fit(
      x = Z_tr,
      y = y_tr,
      weights = V_b,
      family = binomial()
    )
    
    beta_glm_pert[, b] <- coef(fit_b)
  }
  
  beta_glm_pert
}

# Parallel GLM Perturb
make_glm_perturb_train_parallel <- function(B_train, seed = 11,
                                            Z_tr = label_split_all$train$Z,
                                            y_tr = label_split_all$train$labeled_data$delta,
                                            n_cores = max(1, detectCores() - 1)) {
  
  n_tr <- nrow(Z_tr)
  p <- ncol(Z_tr)
  
  cl <- makeCluster(n_cores)
  on.exit(stopCluster(cl), add = TRUE)
  
  clusterExport(
    cl,
    varlist = c("Z_tr", "y_tr", "n_tr"),
    envir = environment()
  )
  clusterSetRNGStream(cl, iseed = seed)
  
  beta_list <- parLapply(cl, seq_len(B_train), function(b) {
    V_b <- rbeta(n_tr, 0.5, 1.5) * 4
    
    fit_b <- glm.fit(
      x = Z_tr,
      y = y_tr,
      weights = V_b,
      family = binomial()
    )
    
    coef(fit_b)
  })
  
  beta_glm_pert <- do.call(cbind, beta_list)
  
  if (!all(dim(beta_glm_pert) == c(p, B_train))) {
    stop("Unexpected dimension in beta_glm_pert.")
  }
  
  beta_glm_pert
}
