make_ssl_perturb <- function(betak, Skb, W.hat) {
  p <- nrow(betak)
  B <- ncol(betak)
  
  stopifnot(nrow(Skb) == B)
  stopifnot(nrow(W.hat) == p)
  stopifnot(ncol(W.hat) == ncol(Skb))
  
  beta_ssl_pert <- matrix(NA_real_, nrow = p, ncol = B)
  
  for (b in seq_len(B)) {
    beta_ssl_pert[, b] <- betak[, b] - drop(W.hat %*% Skb[b, ])
  }
  
  beta_ssl_pert
}
