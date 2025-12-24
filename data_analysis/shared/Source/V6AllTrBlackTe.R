
auc_black_test_init<-evaluate_beta(beta=betadelta_all,
                                   C_tr=label_split_all$train$labeled_data$C, Z_tr=label_split_all$train$Z, delta_tr=label_split_all$train$labeled_data$delta,   # training half                        
                                   C_te=label_split_black$test$labeled_data$C, Z_te=label_split_black$test$Z, delta_te=label_split_black$test$labeled_data$delta   # test  half 
)
auc_black_test_init$auc

lp_beta_blacktest_delta<-drop(label_split_black$test$Z %*% betadelta_all)
concord_beta_blacktest_delta<-Q(lp_beta_blacktest_delta, C=label_split_black$test$labeled_data$C,
                                delta = label_split_black$test$labeled_data$delta )



auc_black_test_ssl<-evaluate_beta(beta=betaSSL_all,
                                  C_tr=label_split_all$train$labeled_data$C, Z_tr=label_split_all$train$Z, delta_tr=label_split_all$train$labeled_data$delta,   # training half                        
                                  C_te=label_split_black$test$labeled_data$C, Z_te=label_split_black$test$Z, delta_te=label_split_black$test$labeled_data$delta   # test  half 
)
auc_black_test_ssl$auc

lp_beta_blacktest_ssl<-drop(label_split_black$test$Z %*% betaSSL_all)
concord_beta_blacktest_ssl<-Q(lp_beta_blacktest_ssl, C=label_split_black$test$labeled_data$C,
                              delta = label_split_black$test$labeled_data$delta )


auc_black_test_glm<-evaluate_beta(beta=beta_glm_all,
                                  C_tr=label_split_all$train$labeled_data$C, Z_tr=label_split_all$train$Z, delta_tr=label_split_all$train$labeled_data$delta,   # training half                        
                                  C_te=label_split_black$test$labeled_data$C, Z_te=label_split_black$test$Z, delta_te=label_split_black$test$labeled_data$delta   # test  half 
)
auc_black_test_glm$auc

lp_beta_blacktest_glm<-drop(label_split_black$test$Z %*% beta_glm_all)
concord_beta_blacktest_glm<-Q(lp_beta_blacktest_glm, C=label_split_black$test$labeled_data$C,
                              delta = label_split_black$test$labeled_data$delta )