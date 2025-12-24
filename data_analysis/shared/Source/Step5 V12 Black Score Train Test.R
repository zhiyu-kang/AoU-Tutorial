version <- "V12"

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
prepared_rdaBlack<-file.path(proj.dir, paste0("RA_model_inputs_Black_", version, ".rda"))
load(prepared_rda)
load(prepared_rdaBlack)
#-------------------------------------------------------------------------------
# Read Black covariates CSV
#-------------------------------------------------------------------------------
black_cov_file <- file.path(
  proj.dir,
  paste0("RA_Black_covariates_X10_plusTop10SNPs_", version, ".csv")
)

stopifnot(file.exists(black_cov_file))

RA_Black_NewSNPS <- readr::read_csv(black_cov_file)

dplyr::glimpse(RA_Black_NewSNPS)

#===================================
#Race Specific
#=====================================
Black_specific_snps <- c(
  "8:128564231:T:C",
  "18:3542249:T:C",
  "18:12880207:A:G",
  "19:35722170:A:G",
  "4:48218822:G:A",
  "9:34710263:G:A",
  "1:2552522:G:A",
  "5:134503843:C:T",
  "15:69699078:G:A",
  "11:2301990:G:A"
)

stopifnot(all(Black_specific_snps %in% names(RA_Black_NewSNPS)))

#---------------------------------------------------------------
# Match training / test IDs to RA_Black_NewSNPS by person_id
#---------------------------------------------------------------
# 1) Get row indices in RA_Black_NewSNPS for train / test
idx_tr <- match(id_black_tr, RA_Black_NewSNPS$person_id)
idx_te <- match(id_black_te, RA_Black_NewSNPS$person_id)
idx_unlab<-match(id_black_unlab, RA_Black_NewSNPS$person_id)

# Optional sanity checks
sum(is.na(idx_tr))  # how many train IDs not found?
sum(is.na(idx_te))  # how many test IDs not found?

# 2) Extract SNP matrices for those IDs
Z_black_tr_other <- as.matrix(
  RA_Black_NewSNPS[idx_tr, Black_specific_snps, drop = FALSE]
)

Z_black_te_other <- as.matrix(
  RA_Black_NewSNPS[idx_te, Black_specific_snps, drop = FALSE]
)
Z_black_unlabel_other<-as.matrix(
  RA_Black_NewSNPS[idx_unlab, Black_specific_snps, drop = FALSE]
  )

#--------------------------------------------------------------
## Keep only complete cases (no NAs) in train / test
## based on Z_black_* and drop same rows from label_split_black
## ----------------------------------------------------------

# Training
keep_tr <- stats::complete.cases(Z_black_tr_other)
sum(!keep_tr)  # number of rows dropped from train

Z_black_tr_other <- Z_black_tr_other[keep_tr, , drop = FALSE]
id_black_tr      <- id_black_tr[keep_tr]

# make sure lengths match
stopifnot(
  length(keep_tr) == nrow(label_split_black$train$Z),
  length(keep_tr) == nrow(label_split_black$train$labeled_data),
  length(keep_tr) == length(label_split_black$train$id)
)

label_split_black$train$Z            <- label_split_black$train$Z[keep_tr, , drop = FALSE]
label_split_black$train$labeled_data <- label_split_black$train$labeled_data[keep_tr, , drop = FALSE]
label_split_black$train$id           <- label_split_black$train$id[keep_tr]

# Test
keep_te <- stats::complete.cases(Z_black_te_other)
sum(!keep_te)  # number of rows dropped from test

Z_black_te_other <- Z_black_te_other[keep_te, , drop = FALSE]
id_black_te      <- id_black_te[keep_te]

stopifnot(
  length(keep_te) == nrow(label_split_black$test$Z),
  length(keep_te) == nrow(label_split_black$test$labeled_data),
  length(keep_te) == length(label_split_black$test$id)
)

label_split_black$test$Z            <- label_split_black$test$Z[keep_te, , drop = FALSE]
label_split_black$test$labeled_data <- label_split_black$test$labeled_data[keep_te, , drop = FALSE]
label_split_black$test$id           <- label_split_black$test$id[keep_te]

# ---------------------------------------------------------
# Unlabeled: keep only complete cases in Z_black_unlabel_other
# ---------------------------------------------------------
keep_unlab <- stats::complete.cases(Z_black_unlabel_other)
sum(!keep_unlab)  # number of unlabeled rows dropped

Z_black_unlabel_other <- Z_black_unlabel_other[keep_unlab, , drop = FALSE]
# Drop the same unlabeled subjects from the original unlabeled Z matrix
Z_unlabeled_mat_black <- Z_unlabeled_mat_black[keep_unlab, , drop = FALSE]

# if you track unlabeled IDs / indices, filter them too
idx_unlab <- idx_unlab[keep_unlab]
unlabeled.black <- unlabeled.black[keep_unlab, , drop = FALSE]
# Files
glm.file   <- file.backlog2(proj.dir, "Black_GLM_",   "rda", version)
delta.file <- file.backlog2(proj.dir, "Black_DELTA_", "rda", version)
ssl.file   <- file.backlog2(proj.dir, "Black_SSL_",   "rda", version)           # final betaSSL + timings
ssl.ckpt   <- file.backlog2(proj.dir, "Black_SSL_CKPT_", "rda", version)        # batch checkpoint


#===============================================================================
# Parameters
#===============================================================================
if (!exists("Nperturb")) Nperturb <- 1000L
p <- ncol(label_split_black$train$Z)+1
nL_tr   <- nrow(label_split_black$train$labeled_data)
nU      <- nrow(Z_unlabeled_mat_black)
n_black   <- nL_tr + nU


#===============================================================================
# 1) Supervised baseline (GLM)  -----------------------------------------------
#===============================================================================
if (file.exists(glm.file)) {
  load(glm.file)  # loads: beta_glm_all, T_all_GLM
} else {
  oldsnpscoreblack_glm_tr<-drop(label_split_black$train$Z %*%beta_glm_all)
  Z_blackscore_glm_tr<-cbind(Z_black_tr_other,oldsnpscoreblack_glm_tr)
  
  oldsnpscoreblack_glm_te<-drop(label_split_black$test$Z %*%beta_glm_all)
  Z_blackscore_glm_te<-cbind(Z_black_te_other,oldsnpscoreblack_glm_te)
  
  
  
  
  fit_tr_betaglmblackscore <- glm.fit(
    x = Z_blackscore_glm_tr,
    y = label_split_black$train$labeled_data$delta,
    family = binomial()
  )
  beta_glm_blackscore <- coef(fit_tr_betaglmblackscore)
  
  # 
  auc_black_glmscore<-evaluate_beta(beta_glm_blackscore,
                                    C_tr=label_split_black$train$labeled_data$C, Z_tr=Z_blackscore_glm_tr, delta_tr=label_split_black$train$labeled_data$delta,   # training half
                                    C_te=label_split_black$test$labeled_data$C, Z_te=Z_blackscore_glm_te, delta_te=label_split_black$test$labeled_data$delta   # test  half 
  )
  # 0.7196649
  auc_black_glmscore$auc
  lp_beta_black_glm_score<-drop(Z_blackscore_glm_te %*% beta_glm_blackscore)
  # 0.5200701
  concord_beta_black_glm_score<-Q(lp_beta_black_glm_score, C=label_split_black$test$labeled_data$C,
                                  delta = label_split_black$test$labeled_data$delta )
  
  save(beta_glm_blackscore,auc_black_glmscore,concord_beta_black_glm_score, file = glm.file)
  
}


#===============================================================================
# 2) Δ-init: bandwidth, kernel, init beta --------------------------------------
#===============================================================================
if (file.exists(delta.file)) {
  load(delta.file)  # loads: h_all, KC_all, betadelta_all, T_all_delta
} else {
  oldsnpscoreblack_delta_tr<-drop(label_split_black$train$Z %*%betadelta_all)
  Z_blackscore_delta_tr<-cbind(Z_black_tr_other,oldsnpscoreblack_delta_tr)
  
  oldsnpscoreblack_delta_te<-drop(label_split_black$test$Z %*%betadelta_all)
  Z_blackscore_delta_te<-cbind(Z_black_te_other,oldsnpscoreblack_delta_te)
  
  h_black <- sd(label_split_black$train$labeled_data$C) /
    (sum(label_split_black$train$labeled_data$delta))^0.25
  
  
  KC_black <- dnorm(
    as.matrix(dist(label_split_black$train$labeled_data$C / h_black, diag = TRUE, upper = TRUE))
  ) / h_black
  
  betadelta_black_score <- init.beta(
    delta = label_split_black$train$labeled_data$delta,
    Z     = Z_blackscore_delta_tr,
    KC    = KC_black
  )
  
  
  auc_black_betadelta_score<-evaluate_beta(beta=betadelta_black_score,
                                           C_tr=label_split_black$train$labeled_data$C, Z_tr=Z_blackscore_delta_tr, delta_tr=label_split_black$train$labeled_data$delta,   # training half
                                           C_te=label_split_black$test$labeled_data$C, Z_te=Z_blackscore_delta_te, delta_te=label_split_black$test$labeled_data$delta   # test  half 
  )
  # 0.7236111
  auc_black_betadelta_score$auc
  lp_beta_black_delta_score<-drop(Z_blackscore_delta_te %*% betadelta_black_score)
  
  # 0.5765668
  concord_beta_black_delta_score<-Q(lp_beta_black_delta_score, C=label_split_black$test$labeled_data$C,delta = label_split_black$test$labeled_data$delta)
  save(h_black, KC_black,auc_black_betadelta_score,concord_beta_black_delta_score, betadelta_black_score, file = delta.file)
}


#===============================================================================
# 3) SSL: batched parallel perturbations + W-hat + betaSSL   (BLACK; ROBUST LOGIC)
#===============================================================================
if (!exists("link"))  link  <- function(x) plogis(x)
if (!exists("dlink")) dlink <- function(x) { p <- plogis(x); p*(1 - p) }

# ensure sequential backend unless you explicitly register a cluster elsewhere
if (requireNamespace("foreach", quietly = TRUE)) foreach::registerDoSEQ()

resume <- FALSE
if (file.exists(ssl.ckpt)) {
  load(ssl.ckpt)   # expects: ibatch, Sk_black, h1_black, batch.cut, nbatch, Nperturb
  # make sure holders exist after resume
  if (!exists("betak_black")) betak_black <- matrix(0, nrow = p,        ncol = Nperturb)
  if (!exists("Skb_black"))   Skb_black   <- matrix(0, nrow = Nperturb, ncol = p)
  resume <- TRUE
} else {
  # ---------- prep: Sk_black & h1_black ----------
  T_ssl_prep <- tictoc({
    oldsnpscoreblack_ssl_tr <- drop(label_split_black$train$Z %*% betaSSL_all)
    Z_blackscore_ssl_tr     <- cbind(Z_black_tr_other, oldsnpscoreblack_ssl_tr)
    
    oldsnpscoreblack_ssl_te <- drop(label_split_black$test$Z %*% betaSSL_all)
    Z_blackscore_ssl_te     <- cbind(Z_black_te_other, oldsnpscoreblack_ssl_te)
    
    oldsnpscoreblack_unlabel <- drop(Z_unlabeled_mat_black%*% betaSSL_all)
    Z_unlabelscore_mat_black <- cbind(Z_black_unlabel_other, oldsnpscoreblack_unlabel)
    
    beta.std_black <- betadelta_black_score / sqrt(sum(betadelta_black_score^2))
    lp_black       <- drop(Z_unlabelscore_mat_black %*% beta.std_black)
    sdlp_black     <- sd(lp_black)
    h1_black       <- sdlp_black / (sum(unlabeled.black$DELTA))^0.3
    
    Sk_black <- numeric(p)
    Sk_black[1:p] <- Sk_sym(
      lp_black,
      Z  = Z_unlabelscore_mat_black,
      Xk = unlabeled.black$X,
      Dk = unlabeled.black$DELTA,
      Ct = unlabeled.black$C,
      dnorm,
      h1_black
    )
  })
  
  # ---------- batching plan ----------
  if (!exists("Nperturb")) Nperturb <- 1000L
  if (!exists("np"))       np <- max(1L, parallel::detectCores() - 1L)
  
  bsize     <- min(4L, np)  # small batches to avoid memory spikes; adjust if you like
  batch.cut <- c(bsize * ((1:ceiling(Nperturb / bsize)) - 1L), Nperturb)
  nbatch    <- length(batch.cut) - 1L
  
  betak_black <- matrix(0, nrow = p,        ncol = Nperturb)
  Skb_black   <- matrix(0, nrow = Nperturb, ncol = p)
}
istart <- if (resume) ibatch + 1L else 1L  # <-- fix resume start

# ---------- export heavy objects to workers once ----------
# (kept as-is; with doSEQ above this is a no-op unless you register a cluster)
if (exists("cl")) {
  parallel::clusterExport(
    cl,
    c("init.beta.perturb","Sk_sym_perturb","Sk_sym","W_hat_adaPCA_ridge",
      "label_split_black","KC_black","betadelta_black_score","Z_unlabeled_mat_black",
      "unlabeled.black","h1_black","p","nL_tr","n_black","link","dlink",
      "Z_black_tr_other","Z_black_te_other","Z_black_unlabel_other","betaSSL_all",
      "Z_blackscore_ssl_tr","Z_blackscore_ssl_te","Z_unlabelscore_mat_black"),
    envir = environment()
  )
}

szMB <- function(x) as.numeric(object.size(x))/1048576  # optional RAM helper

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
      V_black <- rbeta(n_black, 0.5, 1.5) * 4
      
      bk <- init.beta.perturb(
        delta = label_split_black$train$labeled_data$delta,
        Z     = Z_blackscore_ssl_tr,
        KC    = KC_black,
        V     = V_black[1:nL_tr],
        init  = betadelta_black_score,
        link  = link,
        dlink = dlink
      )
      
      # standardize & score on unlabeled  (compute s like robust path)
      s      <- sqrt(sum(bk^2))
      bk.std <- bk / s
      lp_p   <- Z_unlabelscore_mat_black %*% bk.std
      
      Skb <- Sk_sym_perturb(
        lp_p,
        Z  = Z_unlabelscore_mat_black,
        Xk = unlabeled.black$X,
        Dk = unlabeled.black$DELTA,
        Ct = unlabeled.black$C,
        dnorm,
        h1_black,
        matrix(V_black)
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
        V_black <- rbeta(n_black, 0.5, 1.5) * 4
        bk <- init.beta.perturb(
          delta = label_split_black$train$labeled_data$delta,
          Z     = Z_blackscore_ssl_tr,
          KC    = KC_black,
          V     = V_black[1:nL_tr],
          init  = betadelta_black_score,
          link  = link,
          dlink = dlink
        )
        s <- sqrt(sum(bk^2)); if (!is.finite(s) || s <= .Machine$double.eps) next
        bk.std <- bk / s
        lp_p   <- (Z_unlabelscore_mat_black %*% bk.std)[, , drop = FALSE]
        
        Skb <- Sk_sym_perturb(
          lp_p,
          Z  = Z_unlabelscore_mat_black,
          Xk = unlabeled.black$X,
          Dk = unlabeled.black$DELTA,
          Ct = unlabeled.black$C,
          dnorm, h1_black, matrix(V_black)
        )
        stopifnot(is.numeric(Skb), length(Skb) == p, all(is.finite(Skb)))
        
        # write-through using the global replicate id
        j_global <- bpos[j]
        betak_black[, j_global] <- bk
        Skb_black[j_global, ]   <- Skb
        
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
    
    betak_black[, bpos[good]] <- betak_chunk
    Skb_black[bpos[good], ]   <- Skb_chunk
    
    message(sprintf(
      "[SSL] Batch %d/%d done. (perturb %d..%d) [RAM est: betak=%.1fMB, Skb=%.1fMB]",
      ibatch, nbatch, min(bpos), max(bpos),
      szMB(betak_black), szMB(Skb_black)
    ))
    
    # checkpoint (mirror robust path; keep compress=FALSE to avoid spikes)
    save(ibatch, betak_black, Skb_black, Sk_black, h1_black, batch.cut, nbatch, Nperturb,
         file = ssl.ckpt, compress = FALSE)
    
    if ((ibatch %% 3L) == 0L) gc(FALSE)
  }
})


# ---------- post: W-hat, betaSSL, eval ----------

Wh          <- W_hat_adaPCA_ridge(betak_black, Skb_black)
W.hat_black   <- Wh$W.hat
betaSSL_black_score <- betadelta_black_score - drop(W.hat_black %*% Sk_black)

auc_black_ssl_score <- evaluate_beta(
  beta     = betaSSL_black_score,
  C_tr     = label_split_black$train$labeled_data$C,
  Z_tr     = Z_blackscore_ssl_tr,
  delta_tr = label_split_black$train$labeled_data$delta,
  C_te     = label_split_black$test$labeled_data$C,
  Z_te     = Z_blackscore_ssl_te,
  delta_te = label_split_black$test$labeled_data$delta
)

lp_beta_black_SSL_score <- drop(Z_blackscore_ssl_te %*% betaSSL_black_score)
concord_beta_black_SSL_score <- Q(lp_beta_black_SSL_score,
                                  C     = label_split_black$test$labeled_data$C,
                                  delta = label_split_black$test$labeled_data$delta)
auc_black_ssl_score$auc

save(betaSSL_black_score, auc_black_ssl_score, concord_beta_black_SSL_score,
     betak_black, Skb_black, Sk_black, h1_black, W.hat_black,
     file = ssl.file)

if (file.exists(ssl.ckpt)) file.remove(ssl.ckpt)




