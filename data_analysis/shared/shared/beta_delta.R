init.beta = function(delta,Z, KC, init = rep(0,ncol(Z)), tol=1e-7,
                     maxit = 100, min.factor = 0.75,
                     ls.factor = 0.75, max.move = 1,
                     link = expit, dlink = dexpit)
{
  n = nrow(Z)
  KCd = drop(KC%*%delta)
  hC = rep(0,n)
  oldscore = NULL
  
  for(k in 1:maxit) 
  {
    lp = drop(Z%*%init)
    hC.flag = rep(TRUE,n)
    gij = wZbar = matrix(0,n,n)
    hHess = rep(0,n)
    for(kk in 1:maxit)
    {
      # print(hC[hC.flag])
      lij = outer(hC[hC.flag],lp,"+")
      gij[hC.flag,] = link(lij)
      tmp = KC[hC.flag,]*gij[hC.flag,]
      wZbar[hC.flag,] = KC[hC.flag,]*dlink(lij)
      if(sum(hC.flag)>=2)
      {
        hscore = apply(tmp,1,sum)-KCd[hC.flag]
        hHess[hC.flag] = apply(wZbar[hC.flag,],1,sum)
      }else
      {
        hscore = sum(tmp)-KCd[hC.flag]
        hHess[hC.flag] = sum(wZbar[hC.flag,])
      }
      
      dhC = hscore/hHess[hC.flag]
      dhC = sign(dhC)*pmin(abs(dhC),max.move)
      kk.flag = abs(hscore) > tol
      if(!any(kk.flag))
        break
      hC[hC.flag][kk.flag] = hC[hC.flag][kk.flag] - dhC[kk.flag]
      hC.flag[hC.flag] = kk.flag
    }
    if(kk >= maxit)
      stop("Numerical error when computing h0(Ci)")
    Zbar =  (wZbar%*%Z) / hHess 
    
    gi = link(hC+lp)
    bscore = drop(t(Z)%*% (delta - gi))
    if(!is.null(oldscore))
      if(((sum(oldscore^2)*min.factor) <= sum(bscore^2)))
      {
        init = init+dinit
        dinit = dinit*ls.factor
        if(max(abs(dinit))<tol)
        {
          if(max(abs(oldscore)) > 1e-6)
            warning(paste("Algorithm stops in line-search. Target tol: ",
                          tol, ". Current tol: ", max(abs(oldscore)),
                          ". ", sep = ''))
          break
        }
        init = init - dinit
        next
      }
    oldscore = bscore
    bHess = t(dlink(hC+lp)*Z) %*% (Zbar-Z)
    dinit = solve(bHess,bscore)
    if(all(abs(bscore)<tol))
      break
    # print(rbind(init,bscore,dinit))
    init = init - dinit
  }
  if(k >=maxit)
    stop("Numerical error when computing beta_delta")
  
  return(init)
}