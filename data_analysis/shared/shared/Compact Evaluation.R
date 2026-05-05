outer_layer_concordance_split <- function(beta_mat,
                                          train,
                                          test,
                                          n_cores = max(1, detectCores() - 1),
                                          seed = 1) {
  outer_layer_concordance_parallel(
    beta_mat = beta_mat,
    C_tr     = train$labeled_data$C,
    Z_tr     = train$Z,
    delta_tr = train$labeled_data$delta,
    C_te     = test$labeled_data$C,
    Z_te     = test$Z,
    delta_te = test$labeled_data$delta,
    n_cores  = n_cores,
    seed     = seed
  )
}

two_layer_auc_uq_split_batched <- function(beta_mat,
                                           train,
                                           test,
                                           B_test = 100,
                                           n_cores = 3,
                                           seed = 1,
                                           batch_size = 30,
                                           save_file = "auc_uq_checkpoint.rda") {
  two_layer_auc_uq_parallel_batched(
    beta_mat   = beta_mat,
    C_tr       = train$labeled_data$C,
    Z_tr       = train$Z,
    delta_tr   = train$labeled_data$delta,
    C_te       = test$labeled_data$C,
    Z_te       = test$Z,
    delta_te   = test$labeled_data$delta,
    B_test     = B_test,
    n_cores    = n_cores,
    seed       = seed,
    batch_size = batch_size,
    save_file  = save_file
  )
}