# data_io.R — generic helpers for directories, GCS, and CSV prep

ensure_dirs <- function(paths) {
  invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))
}

gcs_init <- function(bucket = Sys.getenv("WORKSPACE_BUCKET"),
                     keyfile = Sys.getenv("GCS_AUTH_FILE", ""),
                     quiet = FALSE) {
  if (!requireNamespace("googleCloudStorageR", quietly = TRUE)) {
    install.packages("googleCloudStorageR")
  }
  suppressPackageStartupMessages(library(googleCloudStorageR))
  
  if (nzchar(keyfile)) {
    googleCloudStorageR::gcs_auth(keyfile)
  } else {
    googleCloudStorageR::gcs_auth()
  }
  
  if (!nzchar(bucket)) stop("[GCS] WORKSPACE_BUCKET env var is empty.")
  
  googleCloudStorageR::gcs_global_bucket(bucket)
  if (!quiet) message("[GCS] Auth OK. Bucket: ", bucket)
  invisible(bucket)
}

gcs_download_if_needed <- function(object_path, local_path, overwrite = FALSE) {
  if (file.exists(local_path) && !overwrite) {
    message("[GCS] Using cached file: ", local_path)
    return(invisible(local_path))
  }
  
  bucket <- googleCloudStorageR::gcs_get_global_bucket()
  if (is.null(bucket) || !nzchar(bucket)) {
    stop("[GCS] Global bucket not set; call gcs_init().")
  }
  
  message("[GCS] Downloading gs://", bucket, "/", object_path, " -> ", local_path)
  
  googleCloudStorageR::gcs_get_object(
    object_name = object_path,
    bucket      = bucket,
    saveToDisk  = local_path,
    overwrite   = TRUE
  )
  
  invisible(local_path)
}

prepare_datasets <- function(csv_path,
                             genetic_cols,
                             labeled_required_cols,
                             unlabeled_required_cols) {
  if (!file.exists(csv_path)) stop("CSV file not found: ", csv_path)
  
  dat <- read.csv(csv_path, stringsAsFactors = FALSE)
  
  required_cols <- unique(c(genetic_cols, labeled_required_cols, unlabeled_required_cols))
  missing_cols <- setdiff(required_cols, names(dat))
  
  if (length(missing_cols)) {
    stop("Missing required columns in CSV: ", paste(missing_cols, collapse = ", "))
  }
  
  na_counts <- colSums(is.na(dat[genetic_cols]))
  
  labeled <- dat[
    complete.cases(dat[c(labeled_required_cols, genetic_cols)]),
    ,
    drop = FALSE
  ]
  
  unlabeled <- dat[
    complete.cases(dat[c(unlabeled_required_cols, genetic_cols)]),
    ,
    drop = FALSE
  ]
  
  list(
    data      = dat,
    labeled   = labeled,
    unlabeled = unlabeled,
    na_counts = na_counts
  )
}

# Example usage 
# ra_data <- prepare_datasets(
#   csv_path = "your_file.csv",
#   genetic_cols = SNP,
#   labeled_required_cols = c("age_at_survey_event"),
#   unlabeled_required_cols = c("age_at_condition_event", "ra_code_YN", "age_at_last_ehr")
# )
#
# x <- ra_data$data