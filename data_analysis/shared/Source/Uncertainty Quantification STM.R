#===========================================Parameters Preparation======================
# Testing Z and Testing C delta
Z_te_black <- label_split_black$test$Z
C_te_black <- label_split_black$test$labeled_data$C
delta_te_black <- label_split_black$test$labeled_data$delta


# Perturbations
B_train <- 1000
# Bootstraps
B_test  <- 100


#===================================================================All GLM====================================
# All Training 1000
beta_glm_pert_all <- make_glm_perturb_train_parallel(
  B_train = B_train,
  Z_tr    = label_split_all$train$Z,
  y_tr    = label_split_all$train$labeled_data$delta,
  seed    = 1001,
  n_cores = 4
)

conc_glm_alltrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = beta_glm_pert_all,
  C_tr     = label_split_all$train$labeled_data$C,
  Z_tr     = label_split_all$train$Z,
  delta_tr = label_split_all$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_te_black,
  delta_te = delta_te_black,
  n_cores  = 4,
  seed     = 3001
)

uq_glm_alltrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat   = beta_glm_pert_all,
  C_tr       = label_split_all$train$labeled_data$C,
  Z_tr       = label_split_all$train$Z,
  delta_tr   = label_split_all$train$labeled_data$delta,
  C_te       = C_te_black,
  Z_te       = Z_te_black,
  delta_te   = delta_te_black,
  B_test     = B_test,
  n_cores    = 3,
  seed       = 2001,
  batch_size = 30,
  save_file  = file.path(proj.dir, paste0("checkpoint_All_GLM_AUC_", version, ".rda"))
)

uq_glm_alltrain_blacktest
conc_glm_alltrain_blacktest

save(
  beta_glm_pert_all,
  uq_glm_alltrain_blacktest,
  conc_glm_alltrain_blacktest,
  file = file.backlog2(proj.dir, "All_GLM_UQ", "rda", version)
)


#=================================================================Black-GLM===============================================================================
oldsnpscoreblack_glm_tr <- drop(label_split_black$train$Z %*% beta_glm_all)
Z_blackscore_glm_tr <- cbind(Z_black_tr_other, oldsnpscoreblack_glm_tr)

oldsnpscoreblack_glm_te <- drop(label_split_black$test$Z %*% beta_glm_all)
Z_blackscore_glm_te <- cbind(Z_black_te_other, oldsnpscoreblack_glm_te)

# Black-Score Training 1000
beta_glm_pert_black <- make_glm_perturb_train_parallel(
  B_train = B_train,
  Z_tr    = Z_blackscore_glm_tr,
  y_tr    = label_split_black$train$labeled_data$delta,
  seed    = 1001,
  n_cores = 4
)

conc_glm_blacktrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = beta_glm_pert_black,
  C_tr     = label_split_black$train$labeled_data$C,
  Z_tr     = Z_blackscore_glm_tr,
  delta_tr = label_split_black$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_blackscore_glm_te,
  delta_te = delta_te_black,
  n_cores  = 4,
  seed     = 3001
)

uq_glm_blacktrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat   = beta_glm_pert_black,
  C_tr       = label_split_black$train$labeled_data$C,
  Z_tr       = Z_blackscore_glm_tr,
  delta_tr   = label_split_black$train$labeled_data$delta,
  C_te       = C_te_black,
  Z_te       = Z_blackscore_glm_te,
  delta_te   = delta_te_black,
  B_test     = B_test,
  n_cores    = 3,
  seed       = 2001,
  batch_size = 30,
  save_file  = file.path(proj.dir, paste0("checkpoint_Black_GLM_AUC_", version, ".rda"))
)

save(
  beta_glm_pert_black,
  uq_glm_blacktrain_blacktest,
  conc_glm_blacktrain_blacktest,
  file = file.backlog2(proj.dir, "Black-Score_GLM_UQ", "rda", version)
)

#=================================================================All-Delta===========================================================================
# All training perturb:
dim(betak_all)

conc_delta_alltrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = betak_all,
  C_tr     = label_split_all$train$labeled_data$C,
  Z_tr     = label_split_all$train$Z,
  delta_tr = label_split_all$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_te_black,
  delta_te = delta_te_black,
  n_cores  = 3,
  seed     = 3001
)

uq_delta_alltrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat  = betak_all,
  C_tr      = label_split_all$train$labeled_data$C,
  Z_tr      = label_split_all$train$Z,
  delta_tr  = label_split_all$train$labeled_data$delta,
  C_te      = C_te_black,
  Z_te      = Z_te_black,
  delta_te  = delta_te_black,
  B_test    = B_test,
  n_cores   = 3,
  seed      = 2001,
  batch_size = 30,
  save_file = file.path(proj.dir, paste0("checkpoint_All_Delta_AUC_", version, ".rda"))
)
save(
  betak_all,
  uq_delta_alltrain_blacktest,
  conc_delta_alltrain_blacktest,
  file = file.backlog2(proj.dir, "All_Delta_UQ", "rda", version)
)

#============================================================Black-Delta==========================================================================
oldsnpscoreblack_delta_tr <- drop(label_split_black$train$Z %*% betadelta_all)
Z_blackscore_delta_tr <- cbind(Z_black_tr_other, oldsnpscoreblack_delta_tr)

oldsnpscoreblack_delta_te <- drop(label_split_black$test$Z %*% betadelta_all)
Z_blackscore_delta_te <- cbind(Z_black_te_other, oldsnpscoreblack_delta_te)

# Black-Score Training Perturb:
betak_black_delta <- make_delta_perturb_parallel_batched(
  B_train   = B_train,
  Z_tr      = Z_blackscore_delta_tr,
  delta_tr  = label_split_black$train$labeled_data$delta,
  KC        = KC_black,
  init      = betadelta_black_score,
  seed      = 1001,
  n_cores   = 3,
  batch_size = 30,
  save_file = file.path(proj.dir, paste0("checkpoint_betak_black_delta_", version, ".rda"))
)
dim(betak_black_delta)

conc_delta_blacktrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = betak_black_delta ,
  C_tr     = label_split_black$train$labeled_data$C,
  Z_tr     = Z_blackscore_delta_tr,
  delta_tr = label_split_black$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_blackscore_delta_te,
  delta_te = delta_te_black,
  n_cores  = 4,
  seed     = 3001
)

uq_delta_blacktrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat   = betak_black_delta ,
  C_tr       = label_split_black$train$labeled_data$C,
  Z_tr       = Z_blackscore_delta_tr,
  delta_tr   = label_split_black$train$labeled_data$delta,
  C_te       = C_te_black,
  Z_te       = Z_blackscore_delta_te,
  delta_te   = delta_te_black,
  B_test     = B_test,
  n_cores    = 3,
  seed       = 2001,
  batch_size = 30,
  save_file  = file.path(proj.dir, paste0("checkpoint_Black_Delta_AUC_", version, ".rda"))
)

save(
  betak_black_delta,
  uq_delta_blacktrain_blacktest,
  conc_delta_blacktrain_blacktest,
  file = file.backlog2(proj.dir, "Black-Score_Delta_UQ", "rda", version)
)
#=====================================================================All-SSL====================================

beta_ssl_pert_all <- make_ssl_perturb(
  betak = betak_all,
  Skb   = Skb_all,
  W.hat = W.hat_all
)

conc_ssl_alltrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = beta_ssl_pert_all,
  C_tr     = label_split_all$train$labeled_data$C,
  Z_tr     = label_split_all$train$Z,
  delta_tr = label_split_all$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_te_black,
  delta_te = delta_te_black,
  n_cores  = 4,
  seed     = 3001
)

uq_ssl_alltrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat   = beta_ssl_pert_all,
  C_tr       = label_split_all$train$labeled_data$C,
  Z_tr       = label_split_all$train$Z,
  delta_tr   = label_split_all$train$labeled_data$delta,
  C_te       = C_te_black,
  Z_te       = Z_te_black,
  delta_te   = delta_te_black,
  B_test     = B_test,
  n_cores    = 3,
  seed       = 2005,
  batch_size = 30,
  save_file  = file.path(proj.dir, paste0("checkpoint_All_SSL_AUC_", version, ".rda"))
)

uq_ssl_alltrain_blacktest
conc_ssl_alltrain_blacktest

save(
  W.hat_all,
  beta_ssl_pert_all,
  uq_ssl_alltrain_blacktest,
  conc_ssl_alltrain_blacktest,
  file = file.backlog2(proj.dir, "All_SSL_UQ", "rda", version)
)
#=========================================================================Black-SSL
oldsnpscoreblack_ssl_tr <- drop(label_split_black$train$Z %*% betaSSL_all)
Z_blackscore_ssl_tr <- cbind(Z_black_tr_other, oldsnpscoreblack_ssl_tr)

oldsnpscoreblack_ssl_te <- drop(label_split_black$test$Z %*% betaSSL_all)
Z_blackscore_ssl_te <- cbind(Z_black_te_other, oldsnpscoreblack_ssl_te)

beta_ssl_pert_black <- make_ssl_perturb(
  betak = betak_black,
  Skb   = Skb_black,
  W.hat = W.hat_black
)

conc_ssl_blacktrain_blacktest <- outer_layer_concordance_parallel(
  beta_mat = beta_ssl_pert_black,
  C_tr     = label_split_black$train$labeled_data$C,
  Z_tr     = Z_blackscore_ssl_tr,
  delta_tr = label_split_black$train$labeled_data$delta,
  C_te     = C_te_black,
  Z_te     = Z_blackscore_ssl_te,
  delta_te = delta_te_black,
  n_cores  = 4,
  seed     = 3001
)

uq_ssl_blacktrain_blacktest <- two_layer_auc_uq_parallel_batched(
  beta_mat   = beta_ssl_pert_black,
  C_tr       = label_split_black$train$labeled_data$C,
  Z_tr       = Z_blackscore_ssl_tr,
  delta_tr   = label_split_black$train$labeled_data$delta,
  C_te       = C_te_black,
  Z_te       = Z_blackscore_ssl_te,
  delta_te   = delta_te_black,
  B_test     = B_test,
  n_cores    = 3,
  seed       = 2005,
  batch_size = 30,
  save_file  = file.path(proj.dir, paste0("checkpoint_Black_SSL_AUC_", version, ".rda"))
)

uq_ssl_blacktrain_blacktest
conc_ssl_blacktrain_blacktest

save(
  W.hat_black,
  beta_ssl_pert_black,
  uq_ssl_blacktrain_blacktest,
  conc_ssl_blacktrain_blacktest,
  file = file.backlog2(proj.dir, "Black-Score_SSL_UQ", "rda", version)
)

