# data_io.R — shared helpers for GCS + CSV prep

# Ensure directories exist
ensure_dirs <- function(paths) {
  invisible(lapply(paths, dir.create, recursive = TRUE, showWarnings = FALSE))
}

# Initialize GCS (auth + bucket)
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
    # Interactive OAuth in environments like AoU Workbench
    googleCloudStorageR::gcs_auth()
  }
  if (!nzchar(bucket)) stop("[GCS] WORKSPACE_BUCKET env var is empty.")
  
  googleCloudStorageR::gcs_global_bucket(bucket)
  if (!quiet) message("[GCS] Auth OK. Bucket: ", bucket)
  invisible(bucket)
}

# Download a single object from GCS if needed
gcs_download_if_needed <- function(object_path, local_path, overwrite = FALSE) {
  if (file.exists(local_path) && !overwrite) {
    message("[GCS] Using cached file: ", local_path)
    return(invisible(local_path))
  }
  bucket <- googleCloudStorageR::gcs_get_global_bucket()
  if (is.null(bucket) || !nzchar(bucket)) stop("[GCS] Global bucket not set; call gcs_init().")
  
  message("[GCS] Downloading gs://", bucket, "/", object_path, " -> ", local_path)
  googleCloudStorageR::gcs_get_object(object_name = object_path,
                                      bucket      = bucket,
                                      saveToDisk  = local_path,
                                      overwrite   = TRUE)
  invisible(local_path)
}

# Prepare labeled/unlabeled data frames from the CSV
prepare_ra_datasets <- function(csv_path, genetic_cols) {
  if (!file.exists(csv_path)) stop("CSV file not found: ", csv_path)
  RA_Newest <- read.csv(csv_path, stringsAsFactors = FALSE)
  
  # Check columns exist
  missing_cols <- setdiff(genetic_cols, names(RA_Newest))
  if (length(missing_cols)) {
    stop("Missing genetic columns in CSV: ", paste(missing_cols, collapse = ", "))
  }
  
  # NA counts for genetics
  na_counts <- colSums(is.na(RA_Newest[genetic_cols]))
  
  # Labeled: requires age_at_survey_event + all genetics
  labeled_cols_req <- c("age_at_survey_event", genetic_cols)
  if (!all(labeled_cols_req %in% names(RA_Newest))) {
    stop("Labeled required columns missing: ",
         paste(setdiff(labeled_cols_req, names(RA_Newest)), collapse = ", "))
  }
  labeled.allV2 <- RA_Newest[complete.cases(RA_Newest[labeled_cols_req]), ]
  
  # Unlabeled: requires age_at_condition_event, ra_code_YN, age_at_last_ehr + genetics
  unlabeled_cols_req <- c("age_at_condition_event", "ra_code_YN", "age_at_last_ehr", genetic_cols)
  if (!all(unlabeled_cols_req %in% names(RA_Newest))) {
    stop("Unlabeled required columns missing: ",
         paste(setdiff(unlabeled_cols_req, names(RA_Newest)), collapse = ", "))
  }
  unlabeled.all <- RA_Newest[complete.cases(RA_Newest[unlabeled_cols_req]), ]
  
  list(
    RA_Newest      = RA_Newest,
    labeled.allV2  = labeled.allV2,
    unlabeled.all  = unlabeled.all,
    na_counts      = na_counts
  )
}
