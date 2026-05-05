# parallel.R
# Starts a PSOCK cluster, registers foreach + doRNG, and exposes helpers.
# Exports:
#   np  - number of workers
#   cl  - the cluster object
#   stop_cluster_safely(), reset_cluster(), attach_packages_on_workers(), cluster_eval()

# ---- Load deps (works even if utility.R isn't sourced yet) -------------------
if (!exists("load.packlist")) {
  load.packlist <- function(pkgs, quietly = TRUE) {
    for (p in pkgs) {
      if (!requireNamespace(p, quietly = quietly)) install.packages(p)
      suppressPackageStartupMessages(library(p, character.only = TRUE))
    }
  }
}
load.packlist(c("parallel", "doParallel", "foreach", "doRNG"))

# ---- Core count --------------------------------------------------------------
.get_core_count <- function() {
  n_env <- Sys.getenv("N_CORES", unset = NA)
  if (!is.na(n_env) && nchar(n_env) > 0) return(max(1L, as.integer(n_env)))
  n_opt <- getOption("project.cores", default = NA)
  if (!is.na(n_opt)) return(max(1L, as.integer(n_opt)))
  n <- parallel::detectCores(logical = TRUE)
  max(1L, n - 1L)  # leave 1 core free by default
}
np <- .get_core_count()

# ---- Tear down an existing cluster (if any) ----------------------------------
if (exists("cl") && inherits(cl, "cluster")) {
  try(parallel::stopCluster(cl), silent = TRUE)
}

# ---- Create cluster & register foreach ---------------------------------------
cl <- parallel::makeCluster(np, type = "PSOCK")

# Mirror master's library paths on workers (helps when using a non-default lib)
parallel::clusterCall(cl, function(paths) { .libPaths(paths); NULL }, .libPaths())

# Register for foreach
doParallel::registerDoParallel(cl)

# ---- Reproducible RNG across workers ----------------------------------------
seed_default <- as.integer(Sys.getenv("RNG_SEED", "531"))
doRNG::registerDoRNG(seed_default)

# ---- Helpers -----------------------------------------------------------------
stop_cluster_safely <- function() {
  if (exists("cl") && inherits(cl, "cluster")) {
    try(parallel::stopCluster(cl), silent = TRUE)
    assign("cl", NULL, inherits = TRUE)
  }
}

reset_cluster <- function(new_np = NULL, seed = NULL) {
  stop_cluster_safely()
  if (is.null(new_np)) new_np <- .get_core_count()
  assign("np", as.integer(new_np), inherits = TRUE)
  assign("cl", parallel::makeCluster(new_np, type = "PSOCK"), inherits = TRUE)
  parallel::clusterCall(cl, function(paths) { .libPaths(paths); NULL }, .libPaths())
  doParallel::registerDoParallel(cl)
  if (is.null(seed)) seed <- as.integer(Sys.getenv("RNG_SEED", "531"))
  doRNG::registerDoRNG(seed)
  invisible(TRUE)
}

attach_packages_on_workers <- function(pkgs) {
  parallel::clusterCall(cl, function(pkgs) {
    for (p in pkgs) suppressPackageStartupMessages(library(p, character.only = TRUE))
    NULL
  }, pkgs)
}

cluster_eval <- function(expr) {
  parallel::clusterEvalQ(cl, eval.parent(substitute(expr)))
}
