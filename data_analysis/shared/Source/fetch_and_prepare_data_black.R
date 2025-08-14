# 00_prepare_and_save_RA.R
# Cleans RA_data.csv, builds model-ready objects, and saves a versioned .rda

# ---- Config ----
version    <- "v1"
proj.dir   <- "~/shared/project/"
local_csv  <- file.path(proj.dir, "data", "RA_data.csv")
dir.create(dirname(local_csv), recursive = TRUE, showWarnings = FALSE)



# If you already downloaded the CSV to the working dir, move or point to it:
if (!file.exists(local_csv) && file.exists("RA_data.csv")) {
  file.copy("RA_data.csv", local_csv, overwrite = TRUE)
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
RA_Black <- subset(RA_Newest, race == "Black or African American")
# ---- Labeled clean ----
labeled.black.clean <- RA_Black[
  !is.na(RA_Black$age_at_survey_event) &
    apply(!is.na(RA_Black[genetic_cols]), 1, all),
]

labeled.black   <- data.frame(
  C     = labeled.black.clean$age_at_survey_event,
  delta = labeled.black.clean$ra_event_survey
)
# Labeled Z (matrix)
Z_labeled_mat_black <- as.matrix(labeled.black.clean[genetic_cols])
storage.mode(Z_labeled_mat_black) <- "numeric"



# ---- Unlabeled clean ----
unlabeled.black.clean <- RA_Black[
  !is.na(RA_Black$age_at_condition_event) &
    !is.na(RA_Black$ra_code_YN) &
    !is.na(RA_Black$age_at_last_ehr) &
    apply(!is.na(RA_Black[genetic_cols]), 1, all),
]
unlabeled.black <- data.frame(
  X     = unlabeled.black.clean$age_at_condition_event,
  DELTA = unlabeled.black.clean$ra_code_YN,
  C     = unlabeled.black.clean$age_at_last_ehr
)

Z_unlabeled_mat_black <- as.matrix(unlabeled.black.clean[genetic_cols])
storage.mode(Z_unlabeled_mat_black) <- "numeric"



# ---- Save bundle ----
prepared_rda <- file.path(proj.dir, paste0("RA_model_inputs_Black", version, ".rda"))
save(labeled.black, Z_labeled_mat_black,
     unlabeled.black, Z_unlabeled_mat_black,
     genetic_cols, na_counts,
     file = prepared_rda)

cat("[OK] Saved model inputs →", prepared_rda, "\n")
cat(sprintf("[n_labeled=%d | n_unlabeled=%d]\n",
            nrow(labeled.black), nrow(unlabeled.black)))
