# ==============================================================================
# Pseudo data for testing only
# ==============================================================================

set.seed(2025)

n <- 500
p <- 20

SNP <- paste0("SNP", seq_len(p))

x <- data.frame(
  delta    = rbinom(n, 1, 0.35),
  C_survey = runif(n, 0.5, 10),
  DELTA    = rbinom(n, 1, 0.45),
  C_ehr    = runif(n, 0.5, 10),
  X        = rnorm(n),
  race     = sample(
    c("Black or African American", "White", "Asian", "Other"),
    n,
    replace = TRUE,
    prob = c(0.25, 0.45, 0.2, 0.1)
  )
)

Z_sim <- matrix(rbinom(n * p, 2, 0.25), nrow = n, ncol = p)
colnames(Z_sim) <- SNP

x <- cbind(x, as.data.frame(Z_sim))

SNP_black <- SNP[1:10]