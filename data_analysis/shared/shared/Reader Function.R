#===============================================================================
# Helper: load one cached object from an .rda file
#===============================================================================
load_cache <- function(path) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  get(ls(env)[1], envir = env)
}

#===============================================================================
# Helper: make version-tagged cache path
#===============================================================================
make_cache <- function(proj.dir, prefix, version, ext = "rda") {
  file.path(proj.dir, paste0(prefix, "_", version, ".", ext))
}

#===============================================================================
# Helper: one perturbation replicate for the initial estimator
# Same perturbation logic as original SSL block:
# generate V_all, use V_all[1:n_labeled] for init.beta.perturb()
#===============================================================================
fit_init_perturb_one <- function(b,
                                 delta,
                                 Z,
                                 KC,
                                 beta_init,
                                 n_unlabeled,
                                 seed = 531L,
                                 link = plogis,
                                 dlink = function(x) {
                                   p <- plogis(x)
                                   p * (1 - p)
                                 }) {
  
  n_labeled <- length(delta)
  n_all <- n_labeled + n_unlabeled
  
  set.seed(seed + b)
  V_all <- rbeta(n_all, 0.5, 1.5) * 4
  
  beta_b <- init.beta.perturb(
    delta = delta,
    Z     = Z,
    KC    = KC,
    V     = V_all[seq_len(n_labeled)],
    init  = beta_init,
    link  = link,
    dlink = dlink
  )
  
  as.numeric(beta_b)
}

#===============================================================================
# train_init(): point initial estimator + cached perturbed initial estimators
#===============================================================================
train_init <- function(delta,
                       C,
                       Z,
                       cache       = "fit_init_cache.rda",
                       Nperturb    = 1000L,
                       n_unlabeled = 0L,
                       batch_size  = 20L,
                       n_cores     = 1L,
                       seed        = 531L,
                       link        = plogis,
                       dlink       = function(x) {
                         p <- plogis(x)
                         p * (1 - p)
                       }) {
  
  if (file.exists(cache)) {
    message("[INIT] Loading cached result: ", cache)
    return(load_cache(cache))
  }
  
  Z <- as.matrix(Z)
  storage.mode(Z) <- "numeric"
  
  delta <- as.numeric(delta)
  C     <- as.numeric(C)
  
  ok_lab <- complete.cases(delta, C, Z)
  
  delta <- as.numeric(delta[ok_lab])
  C     <- as.numeric(C[ok_lab])
  Z     <- Z[ok_lab, , drop = FALSE]
  
  n <- nrow(Z)
  p <- ncol(Z)
  
  stopifnot(length(delta) == n)
  stopifnot(length(C) == n)
  
  timing_point <- system.time({
    h <- sd(C) / (sum(delta))^0.25
    
    KC <- dnorm(
      as.matrix(dist(C / h, diag = TRUE, upper = TRUE))
    ) / h
    
    beta_init <- init.beta(
      delta = delta,
      Z     = Z,
      KC    = KC
    )
  })
  
  batch_cut <- c(
    batch_size * (seq_len(ceiling(Nperturb / batch_size)) - 1L),
    Nperturb
  )
  nbatch <- length(batch_cut) - 1L
  
  betak <- matrix(NA_real_, nrow = p, ncol = Nperturb)
  
  timing_pert <- system.time({
    for (ibatch in seq_len(nbatch)) {
      
      bpos <- seq.int(batch_cut[ibatch] + 1L, batch_cut[ibatch + 1L])
      
      message(sprintf(
        "[INIT] Batch %d/%d running perturbations %d..%d",
        ibatch, nbatch, min(bpos), max(bpos)
      ))
      
      if (n_cores > 1L) {
        cl <- parallel::makeCluster(n_cores, type = "PSOCK")
        on.exit(parallel::stopCluster(cl), add = TRUE)
        
        parallel::clusterExport(
          cl,
          varlist = c(
            "fit_init_perturb_one",
            "init.beta.perturb",
            "delta", "Z", "KC", "beta_init",
            "n_unlabeled", "seed", "link", "dlink"
          ),
          envir = environment()
        )
        
        beta_list <- parallel::parLapply(cl, bpos, function(b) {
          fit_init_perturb_one(
            b           = b,
            delta       = delta,
            Z           = Z,
            KC          = KC,
            beta_init   = beta_init,
            n_unlabeled = n_unlabeled,
            seed        = seed,
            link        = link,
            dlink       = dlink
          )
        })
        
        parallel::stopCluster(cl)
        
      } else {
        beta_list <- lapply(bpos, function(b) {
          fit_init_perturb_one(
            b           = b,
            delta       = delta,
            Z           = Z,
            KC          = KC,
            beta_init   = beta_init,
            n_unlabeled = n_unlabeled,
            seed        = seed,
            link        = link,
            dlink       = dlink
          )
        })
      }
      
      betak[, bpos] <- do.call(
        cbind,
        lapply(beta_list, function(x) matrix(x, nrow = p, ncol = 1))
      )
      
      message(sprintf(
        "[INIT] Batch %d/%d done. [betak=%.1fMB]",
        ibatch, nbatch, as.numeric(object.size(betak)) / 1048576
      ))
      
      gc(FALSE)
    }
  })
  
  fit_init <- list(
    beta         = beta_init,
    beta_pert    = betak,
    h            = h,
    delta        = delta,
    C            = C,
    Z            = Z,
    Nperturb     = Nperturb,
    n_unlabeled  = n_unlabeled,
    seed         = seed,
    timing_point = timing_point,
    timing_pert  = timing_pert
  )
  
  save(fit_init, file = cache, compress = FALSE)
  
  message(sprintf(
    "[INIT] Point: %.2fs | Perturb (%d fits): %.2fs",
    timing_point["elapsed"], Nperturb, timing_pert["elapsed"]
  ))
  
  fit_init
}

#===============================================================================
# Helper: one SSL score perturbation
# Re-generates the same V_all used by train_init() for replicate b
#===============================================================================
fit_ssl_score_perturb_one <- function(b,
                                      betak,
                                      DELTA,
                                      C,
                                      X,
                                      Z,
                                      h1,
                                      n_labeled,
                                      seed = 531L) {
  
  n_unlabeled <- length(DELTA)
  n_all <- n_labeled + n_unlabeled
  
  set.seed(seed + b)
  V_all <- rbeta(n_all, 0.5, 1.5) * 4
  
  beta_b <- betak[, b]
  s <- sqrt(sum(beta_b^2))
  
  if (!is.finite(s) || s <= .Machine$double.eps) {
    return(NULL)
  }
  
  beta_b_std <- beta_b / s
  lp_b <- Z %*% beta_b_std
  
  Skb <- Sk_sym_perturb(
    lp_b,
    Z  = Z,
    Xk = X,
    Dk = DELTA,
    Ct = C,
    dnorm,
    h1,
    matrix(V_all)
  )
  
  if (!all(is.finite(Skb))) {
    return(NULL)
  }
  
  as.numeric(Skb)
}

#===============================================================================
# train_ssl(): SSL estimator using cached fit_init$betak
#===============================================================================
train_ssl <- function(DELTA,
                      C,
                      X,
                      Z,
                      fit_init,
                      cache      = "fit_ssl_cache.rda",
                      Nperturb   = NULL,
                      batch_size = 20L,
                      n_cores    = 1L,
                      seed       = NULL) {
  
  if (file.exists(cache)) {
    message("[SSL] Loading cached result: ", cache)
    return(load_cache(cache))
  }
  
  Z <- as.matrix(Z)
  storage.mode(Z) <- "numeric"
  
  DELTA <- as.numeric(DELTA)
  C     <- as.numeric(C)
  X     <- as.numeric(X)
  
  # Keep rows with complete EHR/unlabeled information.
  ok_unlab <- complete.cases(DELTA, C, X, Z)
  
  DELTA <- DELTA[ok_unlab]
  C     <- C[ok_unlab]
  X     <- X[ok_unlab]
  Z     <- Z[ok_unlab, , drop = FALSE]
  
  if (is.null(Nperturb)) Nperturb <- fit_init$Nperturb
  if (is.null(seed))     seed     <- fit_init$seed
  
  Nperturb <- min(Nperturb, ncol(fit_init$beta_pert))
  
  beta_init <- fit_init$beta
  betak     <- fit_init$beta_pert[, seq_len(Nperturb), drop = FALSE]
  n_labeled <- length(fit_init$delta)
  
  p <- ncol(Z)
  
  stopifnot(length(beta_init) == p)
  stopifnot(nrow(betak) == p)
  stopifnot(nrow(Z) == length(DELTA))
  stopifnot(nrow(Z) == length(C))
  stopifnot(nrow(Z) == length(X))
  
  timing_score <- system.time({
    beta_std <- beta_init / sqrt(sum(beta_init^2))
    lp_u <- drop(Z %*% beta_std)
    h1 <- sd(lp_u) / (sum(DELTA))^0.3
    
    Sk <- Sk_sym(
      lp_u,
      Z  = Z,
      Xk = X,
      Dk = DELTA,
      Ct = C,
      dnorm,
      h1
    )
    
    batch_cut <- c(
      batch_size * (seq_len(ceiling(Nperturb / batch_size)) - 1L),
      Nperturb
    )
    nbatch <- length(batch_cut) - 1L
    
    Skb <- matrix(NA_real_, nrow = Nperturb, ncol = p)
    
    for (ibatch in seq_len(nbatch)) {
      
      bpos <- seq.int(batch_cut[ibatch] + 1L, batch_cut[ibatch + 1L])
      
      message(sprintf(
        "[SSL] Batch %d/%d running perturbations %d..%d",
        ibatch, nbatch, min(bpos), max(bpos)
      ))
      
      if (n_cores > 1L) {
        cl <- parallel::makeCluster(n_cores, type = "PSOCK")
        
        parallel::clusterExport(
          cl,
          varlist = c(
            "fit_ssl_score_perturb_one",
            "Sk_sym_perturb",
            "betak", "DELTA", "C", "X", "Z", "h1",
            "n_labeled", "seed"
          ),
          envir = environment()
        )
        
        Skb_list <- parallel::parLapply(cl, bpos, function(b) {
          fit_ssl_score_perturb_one(
            b         = b,
            betak     = betak,
            DELTA     = DELTA,
            C         = C,
            X         = X,
            Z         = Z,
            h1        = h1,
            n_labeled = n_labeled,
            seed      = seed
          )
        })
        
        parallel::stopCluster(cl)
        
      } else {
        Skb_list <- lapply(bpos, function(b) {
          fit_ssl_score_perturb_one(
            b         = b,
            betak     = betak,
            DELTA     = DELTA,
            C         = C,
            X         = X,
            Z         = Z,
            h1        = h1,
            n_labeled = n_labeled,
            seed      = seed
          )
        })
      }
      
      ok <- vapply(
        Skb_list,
        function(x) is.numeric(x) && length(x) == p && all(is.finite(x)),
        logical(1)
      )
      
      if (any(!ok)) {
        warning(sprintf(
          "[SSL] Dropping %d failed perturbations in batch %d.",
          sum(!ok), ibatch
        ))
      }
      
      good_bpos <- bpos[ok]
      
      if (length(good_bpos) > 0L) {
        Skb[good_bpos, ] <- do.call(
          rbind,
          lapply(Skb_list[ok], function(x) matrix(x, nrow = 1, ncol = p))
        )
      }
      
      message(sprintf(
        "[SSL] Batch %d/%d done. [Skb=%.1fMB]",
        ibatch, nbatch, as.numeric(object.size(Skb)) / 1048576
      ))
      
      gc(FALSE)
    }
    
    ok_all <- complete.cases(Skb)
    
    if (!any(ok_all)) {
      stop("[SSL] No valid perturbation replicates.")
    }
    
    if (any(!ok_all)) {
      warning(sprintf("[SSL] Dropping %d failed perturbation replicates.", sum(!ok_all)))
    }
    
    Skb <- Skb[ok_all, , drop = FALSE]
    betak_use <- betak[, ok_all, drop = FALSE]
  })
  
  timing_post <- system.time({
    Wh <- W_hat_adaPCA_ridge(betak_use, Skb)
    W_hat <- Wh$W.hat
    beta_ssl <- beta_init - drop(W_hat %*% Sk)
  })
  beta_pert <-betak_use- W_hat %*% t(Skb)
  
  fit_ssl <- list(
    beta         = beta_ssl,
    beta_init    = beta_init,
    betak        = betak_use,
    beta_pert    = beta_pert,
    Sk           = Sk,
    Skb          = Skb,
    W_hat        = W_hat,
    h1           = h1,
    C_train      = fit_init$C,
    Z_train      = fit_init$Z,
    delta_train  = fit_init$delta,
    Nperturb     = ncol(betak_use),
    seed         = seed,
    timing_score = timing_score,
    timing_post  = timing_post
  )
  
  save(fit_ssl, file = cache, compress = FALSE)
  
  message(sprintf(
    "[SSL] Score perturb: %.2fs | Post: %.2fs | Total: %.2fs",
    timing_score["elapsed"],
    timing_post["elapsed"],
    (timing_score + timing_post)["elapsed"]
  ))
  
  fit_ssl
}