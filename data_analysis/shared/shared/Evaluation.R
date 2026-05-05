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

auc_survey <- function(fit_beta,
                       delta,
                       C,
                       Z,
                       B_test = 100,
                       n_cores = 3,
                       seed = 1,
                       batch_size = 50,
                       cache = "auc_uq_checkpoint.rda") {
  
  Z <- as.matrix(Z)
  storage.mode(Z) <- "numeric"
  
  ok <- complete.cases(delta, C, Z)
  delta_te <- as.numeric(delta[ok])
  C_te     <- as.numeric(C[ok])
  Z_te     <- Z[ok, , drop = FALSE]
  
  if (is.list(fit_beta)) {
    beta_point <- fit_beta$beta
    beta_mat   <- fit_beta$beta_pert
    
    C_tr     <- fit_beta$C_train
    Z_tr     <- fit_beta$Z_train
    delta_tr <- fit_beta$delta_train
  } else {
    stop("For STM AUC, fit_beta must be a fitted object containing beta, C_train, Z_train, and delta_train.")
  }
  
  if (is.null(beta_mat)) {
    out <- evaluate_beta(
      beta     = beta_point,
      C_tr     = C_tr,
      Z_tr     = Z_tr,
      delta_tr = delta_tr,
      C_te     = C_te,
      Z_te     = Z_te,
      delta_te = delta_te
    )
    return(out$auc)
  }
  
  B_train <- ncol(beta_mat)
  n_te <- nrow(Z_te)
  
  if (file.exists(cache)) {
    load(cache)
    message("Loaded checkpoint: ", cache)
  } else {
    auc_mat <- matrix(NA_real_, nrow = B_train, ncol = B_test)
    completed_batches <- integer(0)
  }
  
  batch_starts <- seq(1, B_train, by = batch_size)
  batch_ends <- pmin(batch_starts + batch_size - 1, B_train)
  n_batches <- length(batch_starts)
  
  for (bb in seq_len(n_batches)) {
    if (bb %in% completed_batches) {
      message("Skipping completed batch ", bb, "/", n_batches)
      next
    }
    
    b_idx <- batch_starts[bb]:batch_ends[bb]
    
    message("Running batch ", bb, "/", n_batches,
            " | perturbations ", min(b_idx), ":", max(b_idx))
    
    cl <- parallel::makeCluster(n_cores)
    
    parallel::clusterExport(
      cl,
      varlist = c("beta_mat",
                  "C_tr", "Z_tr", "delta_tr",
                  "C_te", "Z_te", "delta_te",
                  "B_test", "n_te", "evaluate_beta"),
      envir = environment()
    )
    
    parallel::clusterEvalQ(cl, library(pROC))
    parallel::clusterSetRNGStream(cl, iseed = seed + bb)
    
    auc_list <- parallel::parLapply(cl, b_idx, function(b1) {
      beta_b <- beta_mat[, b1]
      auc_b <- numeric(B_test)
      
      out_full <- evaluate_beta(
        beta     = beta_b,
        C_tr     = C_tr,
        Z_tr     = Z_tr,
        delta_tr = delta_tr,
        C_te     = C_te,
        Z_te     = Z_te,
        delta_te = delta_te
      )
      
      eta_full <- out_full$eta
      
      for (b2 in seq_len(B_test)) {
        idx <- sample.int(n_te, size = n_te, replace = TRUE)
        
        roc_obj <- pROC::roc(
          response  = delta_te[idx],
          predictor = eta_full[idx],
          quiet     = TRUE,
          direction = "<"
        )
        
        auc_b[b2] <- as.numeric(pROC::auc(roc_obj))
      }
      
      auc_b
    })
    
    parallel::stopCluster(cl)
    
    auc_mat[b_idx, ] <- do.call(rbind, auc_list)
    completed_batches <- c(completed_batches, bb)
    
    save(auc_mat, completed_batches, file = cache)
    
    message("Saved checkpoint after batch ", bb)
    gc()
  }
  
  auc_vec <- as.vector(auc_mat)
  
  list(
    auc_mat = auc_mat,
    mean = mean(auc_vec, na.rm = TRUE),
    se = sd(auc_vec, na.rm = TRUE),
    ci = quantile(auc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}


concordance_survey <- function(fit_beta,
                               delta,
                               C,
                               Z,
                               n_cores = max(1, parallel::detectCores() - 1),
                               seed = 1) {
  
  Z <- as.matrix(Z)
  storage.mode(Z) <- "numeric"
  
  ok <- complete.cases(delta, C, Z)
  delta <- as.numeric(delta[ok])
  C     <- as.numeric(C[ok])
  Z     <- Z[ok, , drop = FALSE]
  
  if (is.list(fit_beta)) {
    beta_point <- fit_beta$beta
    beta_mat   <- fit_beta$beta_pert
  } else {
    beta_point <- fit_beta
    beta_mat <- NULL
  }
  
  if (is.null(beta_mat)) {
    lp <- drop(Z %*% beta_point)
    return(Q(lp = lp, C = C, delta = delta))
  }
  
  B_train <- ncol(beta_mat)
  
  cl <- parallel::makeCluster(n_cores)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  parallel::clusterExport(
    cl,
    varlist = c("beta_mat", "Z", "C", "delta", "Q"),
    envir = environment()
  )
  
  parallel::clusterSetRNGStream(cl, iseed = seed)
  
  conc_vec <- unlist(parallel::parLapply(cl, seq_len(B_train), function(b) {
    beta_b <- beta_mat[, b]
    lp_b <- drop(Z %*% beta_b)
    Q(lp = lp_b, C = C, delta = delta)
  }))
  
  list(
    conc_vec = conc_vec,
    mean = mean(conc_vec, na.rm = TRUE),
    se = sd(conc_vec, na.rm = TRUE),
    ci = quantile(conc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}

