#===============================================================================
# 3) SSL: batched parallel perturbations + W-hat + betaSSL   (DROP-IN ROBUST)
#===============================================================================
if (!exists("link"))  link  <- function(x) plogis(x)
if (!exists("dlink")) dlink <- function(x) { p <- plogis(x); p*(1 - p) }

# ensure sequential backend unless you explicitly register a cluster elsewhere   # <<<
if (requireNamespace("foreach", quietly = TRUE)) foreach::registerDoSEQ()       # <<<

resume <- FALSE
if (file.exists(ssl.ckpt)) {
  load(ssl.ckpt)   # expects: ibatch, Sk_all, h1_all, batch.cut, nbatch, Nperturb  # <<<
  # make sure holders exist after resume                                          # <<<
  if (!exists("betak_all")) betak_all <- matrix(0, nrow = p,        ncol = Nperturb)  # <<<
  if (!exists("Skb_all"))   Skb_all   <- matrix(0, nrow = Nperturb, ncol = p)        # <<<
  resume <- TRUE
} else {
  # ---------- prep: Sk_all & h1_all ----------
  T_ssl_prep <- tictoc({
    beta.std_all <- betadelta_all / sqrt(sum(betadelta_all^2))
    lp_all       <- drop(Z_unlabeled_mat_all %*% beta.std_all)
    sdlp_all     <- sd(lp_all)
    h1_all       <- sdlp_all / (sum(unlabeled_all$DELTA))^0.3
    
    Sk_all <- numeric(p)
    Sk_all[1:p] <- Sk_sym(
      lp_all,
      Z  = Z_unlabeled_mat_all,
      Xk = unlabeled_all$X,
      Dk = unlabeled_all$DELTA,
      Ct = unlabeled_all$C,
      dnorm,
      h1_all
    )
  })
  
  # ---------- batching plan ----------
  if (!exists("Nperturb")) Nperturb <- 1000L
  if (!exists("np"))       np <- max(1L, parallel::detectCores() - 1L)
  
  bsize     <- min(4L, np)  # small batches to avoid memory spikes; adjust if you like
  batch.cut <- c(bsize * ((1:ceiling(Nperturb / bsize)) - 1L), Nperturb)
  nbatch    <- length(batch.cut) - 1L
  
  betak_all <- matrix(0, nrow = p,        ncol = Nperturb)
  Skb_all   <- matrix(0, nrow = Nperturb, ncol = p)
}
istart <- if (resume) ibatch + 1L else 1L  # <-- fix resume start

# ---------- export heavy objects to workers once ----------
# (keep as-is; with doSEQ above this is a no-op unless you register a cluster)
if (exists("cl")) {
  parallel::clusterExport(
    cl,
    c("init.beta.perturb","Sk_sym_perturb","Sk_sym","W_hat_adaPCA_ridge",
      "label_split_all","KC_all","betadelta_all","Z_unlabeled_mat_all",
      "unlabeled_all","h1_all","p","nL_tr","n_all","link","dlink"),
    envir = environment()
  )
}

szMB <- function(x) as.numeric(object.size(x))/1048576  # (optional)

# ---------- main loop: foreach %dorng% ----------
T_ssl_loop <- tictoc({
  idx <- if (istart <= nbatch) seq.int(istart, nbatch) else integer(0)  # guard for completed runs
  for (ibatch in idx) {
    bpos <- (batch.cut[ibatch] + 1L):batch.cut[ibatch + 1L]
    if (length(bpos) == 0L) next
    
    # one result per replicate: list(bk=..., sk=...)
    res.list <- foreach(
      b = bpos,
      .packages      = pak.list,
      .options.RNG   = as.integer(531L+ibatch),
      .errorhandling = "pass",
      .combine       = "list",   # keep as list; we'll stitch ourselves
      .multicombine  = FALSE,
      .maxcombine    = 100L
    ) %dorng% {
      V_all <- rbeta(n_all, 0.5, 1.5) * 4
      
      bk <- init.beta.perturb(
        delta = label_split_all$train$labeled_data$delta,
        Z     = label_split_all$train$Z,
        KC    = KC_all,
        V     = V_all[1:nL_tr],
        init  = betadelta_all,
        link  = link,
        dlink = dlink
      )
      
      # standardize & score on unlabeled  (guard zero/NaN norm)                  # <<<
      s <- sqrt(sum(bk^2))                                                       # <<<
      # <<<
      bk.std <- bk / s
      lp_p   <- Z_unlabeled_mat_all %*% bk.std
      
      Skb <- Sk_sym_perturb(
        lp_p,
        Z  = Z_unlabeled_mat_all,
        Xk = unlabeled_all$X,
        Dk = unlabeled_all$DELTA,
        Ct = unlabeled_all$C,
        dnorm,
        h1_all,
        matrix(V_all)
      )
      
      list(bk = as.numeric(bk), sk = as.numeric(Skb))
    }
    
    # --- rewrap singleton last-batch result (foreach may return body directly) ---
    if (length(bpos) == 1L && is.list(res.list) &&
        !is.null(res.list$bk) && !is.null(res.list$sk)) {
      res.list <- list(list(bk = as.numeric(res.list$bk),
                            sk = as.numeric(res.list$sk)))
    }
    
    # ----- handle worker errors/NULLs OUTSIDE foreach -----
    res.list <- lapply(res.list, function(x) if (inherits(x, "error")) NULL else x)
    
    ok <- vapply(
      res.list,
      function(r) {
        is.list(r) &&
          !is.null(r$bk) && is.numeric(r$bk) && length(r$bk) == p && all(is.finite(r$bk)) &&
          !is.null(r$sk) && is.numeric(r$sk) && length(r$sk) == p && all(is.finite(r$sk))
      },
      logical(1)
    )
    
    if (any(!ok)) {
      bad_j <- which(!ok)
      message(sprintf("[SSL] %d/%d replicates failed in batch %d; recomputing serially...",
                      length(bad_j), length(bpos), ibatch))
      for (j in bad_j) {
        V_all <- rbeta(n_all, 0.5, 1.5) * 4
        bk <- init.beta.perturb(
          delta = label_split_all$train$labeled_data$delta,
          Z     = label_split_all$train$Z,
          KC    = KC_all,
          V     = V_all[1:nL_tr],
          init  = betadelta_all,
          link  = link,
          dlink = dlink
        )
        s <- sqrt(sum(bk^2)); if (!is.finite(s) || s <= .Machine$double.eps) next   # <<<
        bk.std <- bk / s
        lp_p   <- (Z_unlabeled_mat_all %*% bk.std)[, , drop = FALSE]
        
        Skb <- Sk_sym_perturb(
          lp_p,
          Z  = Z_unlabeled_mat_all,
          Xk = unlabeled_all$X,
          Dk = unlabeled_all$DELTA,
          Ct = unlabeled_all$C,
          dnorm, h1_all, matrix(V_all)
        )
        stopifnot(is.numeric(Skb), length(Skb) == p, all(is.finite(Skb)))
        
        # write-through using the global replicate id
        j_global <- bpos[j]
        betak_all[, j_global] <- bk
        Skb_all[j_global, ]   <- Skb
        
        # also repair res.list so stitching still works
        res.list[[j]] <- list(bk = as.numeric(bk), sk = as.numeric(Skb))
      }
    }
    
    # ----- stitch (use only good entries; good should be all after fallback) -----
    good <- which(vapply(res.list, is.list, logical(1)))
    betak_chunk <- do.call(cbind, lapply(res.list[good], function(r) matrix(r$bk, nrow = p, ncol = 1)))
    Skb_chunk   <- do.call(rbind, lapply(res.list[good], function(r) matrix(r$sk, nrow = 1, ncol = p, byrow = TRUE)))
    
    stopifnot(nrow(betak_chunk) == p, ncol(betak_chunk) == length(good))
    stopifnot(nrow(Skb_chunk)   == length(good), ncol(Skb_chunk) == p)
    
    betak_all[, bpos[good]] <- betak_chunk
    Skb_all[bpos[good], ]   <- Skb_chunk
    
    message(sprintf("[SSL] Batch %d/%d done. (perturb %d..%d) [RAM est: betak=%.1fMB, Skb=%.1fMB]",  # <<<
                    ibatch, nbatch, min(bpos), max(bpos),                                             # <<<
                    as.numeric(object.size(betak_all))/1048576,                                       # <<<
                    as.numeric(object.size(Skb_all))/1048576))                                        # <<<
    
    # checkpoint: **save only small metadata** (never big matrices)               # <<<
    save(ibatch,betak_all, Skb_all, Sk_all, h1_all, batch.cut, nbatch, Nperturb,                     # <<<
         file = ssl.ckpt, compress = FALSE)                                       # <<<
    
    if ((ibatch %% 3L) == 0L) gc(FALSE)
  }
})

Wh          <- W_hat_adaPCA_ridge(betak_all, Skb_all)
W.hat_all   <- Wh$W.hat
betaSSL_all <- betadelta_all - drop(W.hat_all %*% Sk_all)

save(
  betaSSL_all,
  betak_all, Skb_all, Sk_all, h1_all, W.hat_all,
  file = ssl.file, compress = FALSE
)

if (file.exists(ssl.ckpt)) file.remove(ssl.ckpt)