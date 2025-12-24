init.beta.perturb = function(delta,Z, KC, 
                             V, init = rep(0,ncol(Z)), tol=1e-7,
                             maxit = 100,min.factor = 0.75,
                             ls.factor = 0.75,max.move = 1,
                             link = expit, dlink = dexpit)
{
  n = nrow(Z)
  KC = t(V*KC)
  KCd = drop(KC%*%delta)
  hC = rep(0,n)
  oldscore = NULL
  max.dbeta = max.move
  
  for(k in 1:maxit) 
  {
    # print(k)
    # print(init)
    # print(oldscore)
    lp = drop(Z%*%init)
    hC.flag = rep(TRUE,n)
    gij = wZbar = matrix(0,n,n)
    hHess = rep(0,n)
    for(kk in 1:maxit)
    {
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
    bscore = drop(t(V*Z)%*% (delta - gi))
    if(!is.null(oldscore))
      if((sum(oldscore^2)*min.factor) <= sum(bscore^2))
      {
        init = init+dinit
        dinit = dinit*ls.factor
        if(max(abs(dinit))<tol)
        {
          if(max(abs(oldscore)) > 1e-1)
            stop(paste("Algorithm stops in line-search. Target tol: ",
                       tol, ". Current tol: ", max(abs(oldscore)),
                       ". ", sep = ''))
          
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
    bHess = t(V*dlink(hC+lp)*Z) %*% (Zbar-Z)
    dinit = solve(bHess,bscore)
    dsize = sqrt(sum(dinit^2))
    if(dsize > max.dbeta)
    {
      dinit = dinit/dsize*max.dbeta
    }else
    {
      max.dbeta = dsize
    }
    # print(max(abs(bscore)))
    if(all(abs(bscore)<tol))
      break
    init = init - dinit
  }
  if(k >=maxit)
    stop("Numerical error when computing beta_delta")
  
  return(init)
}
