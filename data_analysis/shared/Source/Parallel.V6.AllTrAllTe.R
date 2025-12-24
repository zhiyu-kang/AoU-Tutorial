rm(list = objects())
version <- "v6"

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
prepared_rda<-file.path(proj.dir, paste0("RA_model_inputs_", version, ".rda"))
prepared_rdaBlack<-file.path(proj.dir, paste0("RA_model_inputs_Black", version, ".rda"))
load(prepared_rda)
load(prepared_rdaBlack)


# Files
glm.file   <- file.backlog2(proj.dir, "ALL_GLM_",   "rda", version)
delta.file <- file.backlog2(proj.dir, "ALL_DELTA_", "rda", version)
ssl.file   <- file.backlog2(proj.dir, "ALL_SSL_",   "rda", version)           # final betaSSL + timings
ssl.ckpt   <- file.backlog2(proj.dir, "ALL_SSL_CKPT_", "rda", version)        # batch checkpoint

#===============================================================================
# Parameters
#===============================================================================
if (!exists("Nperturb")) Nperturb <- 1000L
p <- ncol(label_split_all$train$Z)
nL_tr   <- nrow(label_split_all$train$labeled_data)
nU      <- nrow(unlabeled_all)
n_all   <- nL_tr + nU


#===============================================================================
# 1) Supervised baseline (GLM)  -----------------------------------------------
#===============================================================================
if (file.exists(glm.file)) {
  load(glm.file)  # loads: beta_glm_all, T_all_GLM
} else {
  T_all_GLM <- tictoc({
    fit_tr_betaglmall <- glm.fit(
      x = label_split_all$train$Z,
      y = label_split_all$train$labeled_data$delta,
      family = binomial()
    )
    beta_glm_all <- coef(fit_tr_betaglmall)
    
  })
  auc_all_glm<-evaluate_beta(beta=beta_glm_all,
                             C_tr=label_split_all$train$labeled_data$C, Z_tr=label_split_all$train$Z, delta_tr=label_split_all$train$labeled_data$delta,   # training half
                             C_te=label_split_all$test$labeled_data$C, Z_te=label_split_all$test$Z, delta_te=label_split_all$test$labeled_data$delta   # test  half 
  )
  lp_beta_all_GLM<-drop(label_split_all$test$Z %*% beta_glm_all)
  concord_beta_all_GLM<-Q(lp_beta_all_GLM, C=label_split_all$test$labeled_data$C,delta = label_split_all$test$labeled_data$delta )
  
  save(beta_glm_all,auc_all_glm,concord_beta_all_GLM,T_all_GLM, file = glm.file)
  message(sprintf("[GLM] done in %.2fs", T_all_GLM["elapsed"]))
}


#===============================================================================
# 2) Δ-init: bandwidth, kernel, init beta --------------------------------------
#===============================================================================
if (file.exists(delta.file)) {
  load(delta.file)  # loads: h_all, KC_all, betadelta_all, T_all_delta
} else {
  T_all_delta <- tictoc({
    h_all <- sd(label_split_all$train$labeled_data$C) /
      (sum(label_split_all$train$labeled_data$delta))^0.25
    
    
    KC_all <- dnorm(
      as.matrix(dist(label_split_all$train$labeled_data$C / h_all, diag = TRUE, upper = TRUE))
    ) / h_all
    
    betadelta_all <- init.beta(
      delta = label_split_all$train$labeled_data$delta,
      Z     = label_split_all$train$Z,
      KC    = KC_all
    )
    
  })
  auc_all_betadelta<-evaluate_beta(beta=betadelta_all,
                                   C_tr=label_split_all$train$labeled_data$C, Z_tr=label_split_all$train$Z, delta_tr=label_split_all$train$labeled_data$delta,   # training half
                                   C_te=label_split_all$test$labeled_data$C, Z_te=label_split_all$test$Z, delta_te=label_split_all$test$labeled_data$delta   # test  half 
  )
  lp_beta_all_delta<-drop(label_split_all$test$Z %*% betadelta_all)
  concord_beta_all_delta<-Q(lp_beta_all_delta, C=label_split_all$test$labeled_data$C,delta = label_split_all$test$labeled_data$delta )
  save(h_all, KC_all,auc_all_betadelta,concord_beta_all_delta, betadelta_all, T_all_delta, file = delta.file)
  message(sprintf("[DELTA] done in %.2fs", T_all_delta["elapsed"]))
}

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

# ---------- post: W-hat, betaSSL, eval ----------
T_ssl_post <- tictoc({
  Wh          <- W_hat_adaPCA_ridge(betak_all, Skb_all)
  W.hat_all   <- Wh$W.hat
  betaSSL_all <- betadelta_all - drop(W.hat_all %*% Sk_all)
  
  auc_all_ssl <- evaluate_beta(
    beta     = betaSSL_all,
    C_tr     = label_split_all$train$labeled_data$C,
    Z_tr     = label_split_all$train$Z,
    delta_tr = label_split_all$train$labeled_data$delta,
    C_te     = label_split_all$test$labeled_data$C,
    Z_te     = label_split_all$test$Z,
    delta_te = label_split_all$test$labeled_data$delta
  )
  
  lp_beta_all_SSL <- drop(label_split_all$test$Z %*% betaSSL_all)
  concord_beta_all_SSL <- Q(lp_beta_all_SSL,
                            C     = label_split_all$test$labeled_data$C,
                            delta = label_split_all$test$labeled_data$delta)
})

T_all_SSL <-  T_ssl_loop + T_ssl_post

# ---------- Final save (reduced peak pressure) --------------------------------
# single file; set compress=FALSE to avoid a big serialization spike
save(betaSSL_all, auc_all_ssl, concord_beta_all_SSL,
     betak_all, Skb_all, Sk_all, h1_all, W.hat_all, T_ssl_loop, T_ssl_post, T_all_SSL,
     file = ssl.file, compress = FALSE)    # <<<

# If that STILL spikes memory, split the big matrices:
# saveRDS(betak_all, file.path(proj.dir, paste0("betak_all_", version, ".rds")), compress = FALSE)
# saveRDS(Skb_all,  file.path(proj.dir, paste0("Skb_all_",  version, ".rds")),  compress = FALSE)
# save(betaSSL_all, auc_all_ssl, concord_beta_all_SSL, Sk_all, h1_all, W.hat_all,
#      T_ssl_loop, T_ssl_post, T_all_SSL, file = ssl.file, compress = FALSE)

if (file.exists(ssl.ckpt)) file.remove(ssl.ckpt)
message(sprintf(" loop %.2fs | post %.2fs | total %.2fs",
                as.numeric(T_ssl_loop["elapsed"]),
                as.numeric(T_ssl_post["elapsed"]),
                as.numeric(( T_ssl_loop + T_ssl_post)["elapsed"])))
