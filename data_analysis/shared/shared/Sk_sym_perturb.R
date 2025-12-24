Sk_sym_perturb = function(lp, Z, Xk, Dk, Ct, K, h, V)
{
  n = nrow(Z)
  n.perturb = ncol(V)
  
  # ECDF of G
  X.order = order(Xk)
  C.order = order(Ct)
  GX = rep(0,n)
  Ctail.count = 0
  Ctail.sum = rep(0,n.perturb)
  wZ = matrix(0,n.perturb,n)
  w = rep(0,n.perturb)
  next.X = n
  for(i.X in (n-1):1)
  {
    # print(i.X)
    i = X.order[i.X]
    if(Xk[i]<Xk[X.order[next.X]])
      next.X = i.X
    while (Ctail.count < n) 
    {
      if(Ct[C.order[n-Ctail.count]] < Xk[i])
        break
      Ctail.sum = Ctail.sum + V[C.order[n-Ctail.count],]
      Ctail.count = Ctail.count + 1
    }
    GXi2 = Ctail.sum^2
    
    if( (next.X == n) | (Dk[i]== 0))
      next    
    js = X.order[(next.X+1):n]
    njs = n-next.X
    
    Vij.GXi2 = V[i,]*matrix(t(V[js,]),n.perturb)/GXi2
    w = w + apply(Vij.GXi2,1,sum)
    
    Kbz.GXi2 = K((lp[i,]-
                    matrix(t(lp[js,]),n.perturb))/h)/h * Vij.GXi2
    wZ[,i] = apply(Kbz.GXi2,1,sum)
    wZ[,js] = wZ[,js] - Kbz.GXi2
  }
  
  return(drop(wZ%*%Z)/w)
}