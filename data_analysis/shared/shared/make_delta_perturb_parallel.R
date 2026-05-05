# This is to make a separate beta perturb for initial black score model
make_delta_perturb_parallel <- function(B_train,
                                        Z_tr,
                                        delta_tr,
                                        KC,
                                        init,
                                        seed = 1001,
                                        n_cores = 4) {
  n_tr <- nrow(Z_tr)
  p <- ncol(Z_tr)
  
  cl <- parallel::makeCluster(n_cores)
  on.exit(parallel::stopCluster(cl), add = TRUE)
  
  parallel::clusterExport(
    cl,
    varlist = c("Z_tr", "delta_tr", "KC", "init", "n_tr",
                "init.beta.perturb", "link", "dlink"),
    envir = environment()
  )
  
  parallel::clusterSetRNGStream(cl, iseed = seed)
  
  beta_list <- parallel::parLapply(cl, seq_len(B_train), function(b) {
    V_black <- rbeta(n_tr, 0.5, 1.5) * 4
    
    init.beta.perturb(
      delta = delta_tr,
      Z     = Z_tr,
      KC    = KC,
      V     = V_black,
      init  = init,
      link  = link,
      dlink = dlink
    )
  })
  
  betak <- do.call(cbind, beta_list)
  
  stopifnot(all(dim(betak) == c(p, B_train)))
  
  betak
}

make_delta_perturb_parallel_batched <- function(B_train,
                                                Z_tr,
                                                delta_tr,
                                                KC,
                                                init,
                                                seed = 1001,
                                                n_cores = 4,
                                                batch_size = 30,
                                                save_file = "checkpoint_betak_black_delta.rda") {
  n_tr <- nrow(Z_tr)
  p <- ncol(Z_tr)
  
  if (file.exists(save_file)) {
    load(save_file)  # loads betak, completed_batches
    message("Loaded checkpoint: ", save_file)
  } else {
    betak <- matrix(NA_real_, nrow = p, ncol = B_train)
    completed_batches <- integer(0)
  }
  
  batch_starts <- seq(1, B_train, by = batch_size)
  batch_ends   <- pmin(batch_starts + batch_size - 1, B_train)
  n_batches    <- length(batch_starts)
  
  for (bb in seq_len(n_batches)) {
    if (bb %in% completed_batches) {
      message("Skipping completed batch ", bb, "/", n_batches)
      next
    }
    
    b_idx <- batch_starts[bb]:batch_ends[bb]
    
    message(
      "Running batch ", bb, "/", n_batches,
      " | perturbations ", min(b_idx), ":", max(b_idx)
    )
    
    cl <- parallel::makeCluster(n_cores)
    
    parallel::clusterExport(
      cl,
      varlist = c("Z_tr", "delta_tr", "KC", "init", "n_tr",
                  "init.beta.perturb", "link", "dlink"),
      envir = environment()
    )
    
    parallel::clusterSetRNGStream(cl, iseed = seed + bb)
    
    beta_list <- parallel::parLapply(cl, b_idx, function(b) {
      V_black <- rbeta(n_tr, 0.5, 1.5) * 4
      
      init.beta.perturb(
        delta = delta_tr,
        Z     = Z_tr,
        KC    = KC,
        V     = V_black,
        init  = init,
        link  = link,
        dlink = dlink
      )
    })
    
    parallel::stopCluster(cl)
    
    beta_chunk <- do.call(cbind, beta_list)
    
    stopifnot(all(dim(beta_chunk) == c(p, length(b_idx))))
    
    betak[, b_idx] <- beta_chunk
    
    completed_batches <- c(completed_batches, bb)
    
    save(
      betak,
      completed_batches,
      file = save_file,
      compress = FALSE
    )
    
    message(
      "Saved checkpoint after batch ", bb,
      " | completed ", length(completed_batches), "/", n_batches,
      " batches | ", max(b_idx), "/", B_train, " perturbations"
    )
    
    gc()
  }
  
  if (anyNA(betak)) {
    warning("Some perturbations are still NA. Check failed or skipped batches.")
  }
  
  betak
}