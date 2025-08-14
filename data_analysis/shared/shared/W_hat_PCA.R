require(glmnet)
W_hat_pca = function(betak,Skb,npc = nrow(betak)-1)
{
  p = nrow(betak)
  B = ncol(betak)
  Kp = ncol(Skb)
  Proj = (svd(Skb/sqrt(B), nu = 0, nv = npc)$v)
  PSkb =  Skb %*% Proj
  
  W.hat = matrix(0,p,npc)
  
  for(j in 1:p)
  {
    tmp.ridge = cv.glmnet(PSkb,betak[j,],alpha = 0)
    W.hat[j,]=coef(tmp.ridge,s="lambda.min")[-1]
  }
  
  return(W.hat %*% t(Proj))
}