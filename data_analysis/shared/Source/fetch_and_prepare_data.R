# 00_prepare_and_save_RA.R
# Cleans RA_data.csv, builds model-ready objects, and saves a versioned .rda

# ---- Config ----
version    <- "v2"
proj.dir   <- "~/shared/project/"

#--------------------------
#Load your file from google cloud
#--------------------------
library(googleCloudStorageR)

# Google Cloud Authentication
gcs_auth()

# Set up GCS bucket name
my_bucket <- Sys.getenv("WORKSPACE_BUCKET")  # Enviroment variable

# The name of file you want to download
name_of_file_in_bucket <- "RA_data.csv"
gcs_get_object(
  object_name = "data/RA_data.csv", 
  bucket      = my_bucket,
  saveToDisk  = "RA_data.csv",
  overwrite   = TRUE
)


local_csv  <- file.path(proj.dir, "data", "RA_data.csv")
dir.create(dirname(local_csv), recursive = TRUE, showWarnings = FALSE)

# If you already downloaded the CSV to the working dir, move or point to it:
if (!file.exists(local_csv) && file.exists("RA_data.csv")) {
  file.copy("RA_data2.csv", local_csv, overwrite = TRUE)
}

# ---- Read CSV ----
stopifnot(file.exists(local_csv))
RA_Newest <- read.csv(local_csv, stringsAsFactors = FALSE)

# ---- Genetics columns ----
genetic_cols <- c(
  "X12.111446804.T.C", "X12.45976333.C.G", "X13.39781776.T.C",
  "X14.104920174.G.A", "X14.68287978.G.A", "X1.116738074.C.T",
  "X5.143224856.A.G",  "X6.159082054.A.G", "X6.36414159.G.GA",
  "X9.34710263.G.A"
)
stopifnot(all(genetic_cols %in% names(RA_Newest)))

# ---- Quick NA audit on genetics ----
na_counts <- colSums(is.na(RA_Newest[genetic_cols]))
print(na_counts)

# ---- Labeled clean ----
labeled.all.clean <- RA_Newest[
  !is.na(RA_Newest$age_at_survey_event) &
    apply(!is.na(RA_Newest[genetic_cols]), 1, all),
]

labeled_all   <- data.frame(
  C     = labeled.all.clean$age_at_survey_event,
  delta = labeled.all.clean$ra_event_survey
)
# Labeled Z (matrix)
Z_labeled_mat <- as.matrix(labeled.all.clean[genetic_cols])
storage.mode(Z_labeled_mat) <- "numeric"



# ---- Unlabeled clean ----
unlabeled.all.clean <- RA_Newest[
  !is.na(RA_Newest$age_at_condition_event) &
    !is.na(RA_Newest$ra_code_YN) &
    !is.na(RA_Newest$age_at_last_ehr) &
    apply(!is.na(RA_Newest[genetic_cols]), 1, all),
]
unlabeled.all <- data.frame(
  X     = unlabeled.all.clean$age_at_condition_event,
  DELTA = unlabeled.all.clean$ra_code_YN,
  C     = unlabeled.all.clean$age_at_last_ehr
)

Z_unlabeled_mat <- as.matrix(unlabeled.all.clean[genetic_cols])
storage.mode(Z_unlabeled_mat) <- "numeric"



# ---- Save bundle ----
prepared_rda <- file.path(proj.dir, paste0("RA_model_inputs_", version, ".rda"))
save(labeled_all, Z_labeled_mat,
     unlabeled.all, Z_unlabeled_mat,
     genetic_cols, na_counts,
     file = prepared_rda)

cat("[OK] Saved model inputs →", prepared_rda, "\n")
cat(sprintf("[n_labeled=%d | n_unlabeled=%d]\n",
            nrow(labeled_all), nrow(unlabeled.all)))
