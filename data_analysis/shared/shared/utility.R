sum.I <- function(yy,FUN,Yi,Vi=NULL)
{
  if (FUN=="<"|FUN==">=") { yy <- -yy; Yi <- -Yi}
  pos <- rank(c(yy,Yi),ties.method='f')[1:length(yy)]-rank(yy,ties.method='f')
  if (substring(FUN,2,2)=="=") pos <- length(Yi)-pos
  if (!is.null(Vi)) {
    if(substring(FUN,2,2)=="=") tmpind <- order(-Yi) else  tmpind <- order(Yi)
    ##Vi <- cumsum2(as.matrix(Vi)[tmpind,])
    Vi <- apply(as.matrix(Vi)[tmpind,,drop=F],2,cumsum)
    return(rbind(0,Vi)[pos+1,])
  } else return(pos)
}

expit <- function(x){
  1/(1+exp(-x))
}
dexpit <- function(x){
  expit(x)*(1-expit(x))
}

logit <- function(x){
  log(x/(1-x))
}

loglik2 <- function(beta,h0C){
  sum(data$delta*log(expit(h0C+Z%*%beta)) + (1-data$delta)*log(1-expit(h0C+Z%*%beta)),na.rm=T)
}

ddnorm = function(x)
{
  -x*exp(-x^2/2)/sqrt(2*pi)
}

dddnorm = function(x)
{
  (x^2-1)*exp(-x^2/2)/sqrt(2*pi)
}

loglog = function(x)
{
  -log(-log(x))
}

expexp = function(x)
{
  exp(-exp(-x))
}

dexpexp = function(x)
{
  exp(-exp(-x))*exp(-x)
}

wtd.mean = function(x,wgt)
{
  drop(x%*%wgt)/sum(wgt)
}

wtd.sd = function(x, wgt)
{
  sqrt( drop(((x - wtd.mean(x,wgt))^2)%*% wgt) / sum(wgt))
}

file.backlog2 <- function(dir, prefix, ext, version) {
  dir <- normalizePath(dir, mustWork = FALSE)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  file.path(dir, paste0(prefix, version, ".", ext))
}

split_data <- function(labeled_data, Z_mat, seed = 123) {
  set.seed(seed)
  m <- nrow(labeled_data)
  
  # create a 2‐fold 50/50 split
  foldid <- sample(rep(1:2, length.out = m))
  train_idx <- which(foldid == 1)
  test_idx  <- which(foldid == 2)
  
  # force Z_mat -> numeric matrix
  Z_mat <- as.matrix(Z_mat)
  
  # sanity checks
  stopifnot(nrow(Z_mat) == m)
  
  # subset
  train <- list(
    labeled_data = labeled_data[train_idx, , drop = FALSE],
    Z            = Z_mat[train_idx, , drop = FALSE],
    idx          = train_idx
  )
  test  <- list(
    labeled_data = labeled_data[test_idx,  , drop = FALSE],
    Z            = Z_mat[test_idx,  , drop = FALSE],
    idx          = test_idx
  )
  
  list(
    train  = train,
    test   = test,
    foldid = foldid
  )
}
