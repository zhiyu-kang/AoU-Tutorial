Sk_sym = function(lp, Z, Xk, Dk, Ct, K, h)
{
  n = nrow(Z)
  
  # ECDF of G
  X.order = order(Xk)
  C.sort = sort(Ct)
  Ctail = 0
  wZ = rep(0,n)
  w = 0
  next.X = n
  for(i.X in (n-1):1)
  {
    i = X.order[i.X]
    if(Xk[i]<Xk[X.order[next.X]])
      next.X = i.X
    while (Ctail < n) 
    {
      if(C.sort[n-Ctail] < Xk[i])
        break
      Ctail = Ctail + 1
    }
    
    if( (next.X == n) | (Dk[i]== 0))
      next
    GXi2 = (Ctail/n)^2
    w = w + (n-next.X)/GXi2
    
    js = X.order[(next.X+1):n]
    Kbz = K((lp[i]-lp[js])/h)/h
    wZ[i] = sum(Kbz)/GXi2
    wZ[js] = wZ[js] - Kbz/GXi2
  }
  
  return(drop(wZ%*%Z)/w)
}