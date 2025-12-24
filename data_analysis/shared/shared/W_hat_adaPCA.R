require(glmnet)
W_hat_adaPCA_ridge = function(betak,Skb, a = 2)
{
  p = nrow(betak)
  B = ncol(betak)
  Kp = ncol(Skb)
  
  Skb.sd = apply(Skb, 2, sd)
  Skb.std = scale(Skb)
  eig.var = eigen(var(Skb.std), symmetric = T)
  PSkb =  Skb.std %*% eig.var$vectors
  ada.pen = 1/eig.var$values^a
  ada.pen = ada.pen/mean(ada.pen)
  
  W.hat = matrix(0,p,Kp)
  lambda = rep(0, p)
  
  for(j in 1:p)
  {
    tmp.fit = cv.glmnet(PSkb,betak[j,],alpha = 0, penalty.factor = ada.pen)
    W.hat[j,]=drop(diag(1/Skb.sd) %*% eig.var$vectors %*% coef(tmp.fit,s="lambda.min")[-1])
    lambda[j] = tmp.fit$lambda.min
  }
  
  return(list(W.hat = W.hat, lambda =lambda, 
              ada.pen = ada.pen))
}

W_hat_adaPCA_lasso = function(betak,Skb, a=1)
{
  p = nrow(betak)
  B = ncol(betak)
  Kp = ncol(Skb)
  
  Skb.sd = apply(Skb, 2, sd)
  Skb.std = scale(Skb)
  eig.var = eigen(var(Skb.std), symmetric = T)
  PSkb =  Skb.std %*% eig.var$vectors
  ada.pen = 1/eig.var$values^a
  ada.pen = ada.pen/mean(ada.pen)
  
  W.hat = matrix(0,p,Kp)
  lambda = rep(0, p)
  
  for(j in 1:p)
  {
    tmp.fit = cv.glmnet(PSkb,betak[j,], penalty.factor = ada.pen)
    W.hat[j,]=drop(diag(1/Skb.sd) %*% eig.var$vectors %*% coef(tmp.fit,s="lambda.min")[-1])
    lambda[j] = tmp.fit$lambda.min
  }
  
  return(list(W.hat = W.hat, lambda =lambda, 
              ada.pen = ada.pen))
}