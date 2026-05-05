# This is STM evaluation designed for chunck code
library("pROC")
library("parallel")
source(paste0(shared.dir, "Evaluation.R"))
# AUC from one beta vector on one test set
# Use STM score: eta = phi(C) + Z beta
auc_from_beta <- function(beta,
                          C_tr, Z_tr, delta_tr,
                          C_te, Z_te, delta_te) {
  out <- evaluate_beta(
    beta     = beta,
    C_tr     = C_tr,
    Z_tr     = Z_tr,
    delta_tr = delta_tr,
    C_te     = C_te,
    Z_te     = Z_te,
    delta_te = delta_te
  )
  
  out$auc
}

# Inner-layer bootstrap on the Black test set
boot_auc_given_beta <- function(beta,
                                C_tr, Z_tr, delta_tr,
                                C_te, Z_te, delta_te,
                                B_test = 200,
                                seed = 1) {
  set.seed(seed)
  
  n_te <- nrow(Z_te)
  auc_star <- numeric(B_test)
  
  for (b in seq_len(B_test)) {
    idx <- sample.int(n_te, size = n_te, replace = TRUE)
    
    auc_star[b] <- auc_from_beta(
      beta     = beta,
      C_tr     = C_tr,
      Z_tr     = Z_tr,
      delta_tr = delta_tr,
      C_te     = C_te[idx],
      Z_te     = Z_te[idx, , drop = FALSE],
      delta_te = delta_te[idx]
    )
  }
  
  list(
    auc_hat = auc_from_beta(
      beta     = beta,
      C_tr     = C_tr,
      Z_tr     = Z_tr,
      delta_tr = delta_tr,
      C_te     = C_te,
      Z_te     = Z_te,
      delta_te = delta_te
    ),
    mean = mean(auc_star, na.rm = TRUE),
    se = sd(auc_star, na.rm = TRUE),
    ci = quantile(auc_star, c(0.025, 0.975), na.rm = TRUE),
    auc_star = auc_star
  )
}

# Full two-layer UQ:
# outer layer = perturbed beta
# inner layer = Black test bootstrap
two_layer_auc_uq <- function(beta_mat,
                             C_tr, Z_tr, delta_tr,
                             C_te, Z_te, delta_te,
                             B_test = 200,
                             seed = 1) {
  set.seed(seed)
  
  B_train <- ncol(beta_mat)
  n_te <- nrow(Z_te)
  auc_mat <- matrix(NA_real_, nrow = B_train, ncol = B_test)
  
  for (b1 in seq_len(B_train)) {
    beta_b <- beta_mat[, b1]
    
    for (b2 in seq_len(B_test)) {
      idx <- sample.int(n_te, size = n_te, replace = TRUE)
      
      auc_mat[b1, b2] <- auc_from_beta(
        beta     = beta_b,
        C_tr     = C_tr,
        Z_tr     = Z_tr,
        delta_tr = delta_tr,
        C_te     = C_te[idx],
        Z_te     = Z_te[idx, , drop = FALSE],
        delta_te = delta_te[idx]
      )
    }
  }
  
  auc_vec <- as.vector(auc_mat)
  
  list(
    auc_mat = auc_mat,
    mean = mean(auc_vec, na.rm = TRUE),
    se = sd(auc_vec, na.rm = TRUE),
    ci = quantile(auc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}

# ParallelComputingVersion
two_layer_auc_uq_parallel <- function(beta_mat,
                                      C_tr, Z_tr, delta_tr,
                                      C_te, Z_te, delta_te,
                                      B_test = 200,
                                      n_cores = max(1, detectCores() - 1),
                                      seed = 1) {
  B_train <- ncol(beta_mat)
  n_te <- nrow(Z_te)
  
  cl <- makeCluster(n_cores)
  on.exit(stopCluster(cl), add = TRUE)
  
  clusterExport(
    cl,
    varlist = c("beta_mat",
                "C_tr", "Z_tr", "delta_tr",
                "C_te", "Z_te", "delta_te",
                "B_test", "n_te",
                "evaluate_beta"),
    envir = environment()
  )
  clusterEvalQ(cl, library(pROC))
  clusterSetRNGStream(cl, iseed = seed)
  
  auc_list <- parLapply(cl, seq_len(B_train), function(b1) {
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
  
  auc_mat <- do.call(rbind, auc_list)
  auc_vec <- as.vector(auc_mat)
  
  list(
    auc_mat = auc_mat,
    mean = mean(auc_vec, na.rm = TRUE),
    se = sd(auc_vec, na.rm = TRUE),
    ci = quantile(auc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}



two_layer_auc_uq_parallel_batched <- function(beta_mat,
                                              C_tr, Z_tr, delta_tr,
                                              C_te, Z_te, delta_te,
                                              B_test = 100,
                                              n_cores = 3,
                                              seed = 1,
                                              batch_size = 50,
                                              save_file = "auc_uq_checkpoint.rda") {
  B_train <- ncol(beta_mat)
  n_te <- nrow(Z_te)
  
  # Resume if checkpoint exists
  if (file.exists(save_file)) {
    load(save_file)  # loads auc_mat, completed_batches
    message("Loaded checkpoint: ", save_file)
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
    
    cl <- makeCluster(n_cores)
    
    clusterExport(
      cl,
      varlist = c("beta_mat",
                  "C_tr", "Z_tr", "delta_tr",
                  "C_te", "Z_te", "delta_te",
                  "B_test", "n_te", "evaluate_beta"),
      envir = environment()
    )
    clusterEvalQ(cl, library(pROC))
    clusterSetRNGStream(cl, iseed = seed + bb)
    
    auc_list <- parLapply(cl, b_idx, function(b1) {
      beta_b <- beta_mat[, b1]
      auc_b <- numeric(B_test)
      
      # Solve phi(C) once for this perturbed beta
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
      
      # Bootstrap AUC using eta_full
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
    
    stopCluster(cl)
    
    auc_mat[b_idx, ] <- do.call(rbind, auc_list)
    
    completed_batches <- c(completed_batches, bb)
    
    save(
      auc_mat,
      completed_batches,
      file = save_file
    )
    
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

# Concordance on beta
# Use linear predictor Z beta; Q() already incorporates C through pair eligibility
conc_from_beta <- function(beta,
                           C_tr, Z_tr, delta_tr,
                           C_te, Z_te, delta_te) {
  lp<-drop(Z_te %*%beta)
  
  Q(lp = lp, C = C_te, delta = delta_te)
}

# Concordance from one beta on the Black test set
outer_layer_concordance <- function(beta_mat,
                                    C_tr, Z_tr, delta_tr,
                                    C_te, Z_te, delta_te) {
  B_train <- ncol(beta_mat)
  conc_vec <- numeric(B_train)
  
  for (b in seq_len(B_train)) {
    conc_vec[b] <- conc_from_beta(
      beta     = beta_mat[, b],
      C_tr     = C_tr,
      Z_tr     = Z_tr,
      delta_tr = delta_tr,
      C_te     = C_te,
      Z_te     = Z_te,
      delta_te = delta_te
    )
  }
  
  list(
    conc_vec = conc_vec,
    mean = mean(conc_vec, na.rm = TRUE),
    se = sd(conc_vec, na.rm = TRUE),
    ci = quantile(conc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}

outer_layer_concordance_parallel <- function(beta_mat,
                                             C_tr, Z_tr, delta_tr,
                                             C_te, Z_te, delta_te,
                                             n_cores = max(1, detectCores() - 1),
                                             seed = 1) {
  B_train <- ncol(beta_mat)
  
  cl <- makeCluster(n_cores)
  on.exit(stopCluster(cl), add = TRUE)
  
  clusterExport(
    cl,
    varlist = c("beta_mat", "Z_te", "C_te", "delta_te", "Q"),
    envir = environment()
  )
  
  clusterSetRNGStream(cl, iseed = seed)
  
  conc_vec <- unlist(parLapply(cl, seq_len(B_train), function(b) {
    beta_b <- beta_mat[, b]
    lp_b <- drop(Z_te %*% beta_b)
    
    Q(lp = lp_b, C = C_te, delta = delta_te)
  }))
  
  list(
    conc_vec = conc_vec,
    mean = mean(conc_vec, na.rm = TRUE),
    se = sd(conc_vec, na.rm = TRUE),
    ci = quantile(conc_vec, c(0.025, 0.975), na.rm = TRUE)
  )
}
