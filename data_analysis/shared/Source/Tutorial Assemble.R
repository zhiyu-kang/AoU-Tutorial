#===============================================================================
# Step 1: Prepare tutorial-style data table x
#===============================================================================
version    <- "V5_Commorbities_Showcase"
proj.dir  <- "~/shared/project/"
data.dir  <- file.path(proj.dir, "data")
dir.create(data.dir, recursive = TRUE, showWarnings = FALSE)

library(dplyr)
library(googleCloudStorageR)

#-------------------------------------------------------------------------------
# 0) Download cohort data
#-------------------------------------------------------------------------------

gcs_auth()

my_bucket <- Sys.getenv("WORKSPACE_BUCKET")

name_of_file_in_bucket <- "RA_data_comorbidities.csv"

gcs_get_object(
  object_name = paste0("data/", name_of_file_in_bucket),
  bucket      = my_bucket,
  saveToDisk  = file.path(data.dir, name_of_file_in_bucket),
  overwrite   = TRUE
)

RA_cohort <- read.csv(file.path(data.dir, name_of_file_in_bucket),
                      check.names = FALSE)

stopifnot(exists("RA_cohort"))

#-------------------------------------------------------------------------------
# 1) Define SNP columns
#-------------------------------------------------------------------------------

SNP <- c(
  "12:111446804:T:C", "12:45976333:C:G", "13:39781776:T:C",
  "14:104920174:G:A", "14:68287978:G:A", "1:116738074:C:T",
  "5:143224856:A:G",  "6:159082054:A:G", "6:36414159:G:GA",
  "9:34710263:G:A"
)

stopifnot(all(SNP %in% names(RA_cohort)))

#-------------------------------------------------------------------------------
# 2)tutorial-style table x
#-------------------------------------------------------------------------------
# id, C_survey, delta, X, DELTA, C_ehr, race, SNPs
#
# Mapping from original variables:
# id       = person_id
# C_survey = age_at_survey_event
# delta    = ra_event_survey
# X        = age_at_condition_event
# DELTA    = ra_code_YN
# C_ehr    = age_at_last_ehr
# race     = race
# SNPs     = selected SNP dosage columns

x <- RA_cohort %>%
  transmute(
    id       = as.integer(person_id),
    C_survey = age_at_survey_event,
    delta    = ra_event_survey,
    X        = age_at_condition_event,
    DELTA    = ra_code_YN,
    C_ehr    = age_at_last_ehr,
    race     = race,
    across(all_of(SNP))
  )

# Keep one row per participant for tutorial modeling
x <- x %>%
  arrange(id) %>%
  distinct(id, .keep_all = TRUE)

cat("[INFO] x dimension:\n")
print(dim(x))

cat("[INFO] Number of unique IDs:\n")
print(length(unique(x$id)))

#-------------------------------------------------------------------------------
# 3) Train/test split based on participants with survey outcome
#-------------------------------------------------------------------------------
# Training/testing are defined for survey-labeled participants.
# The SSL step can still use EHR columns X, DELTA, C_ehr from x_train.

idx_labeled <- complete.cases(x[, c("C_survey", "delta", SNP)])

x_labeled <- x[idx_labeled, , drop = FALSE]

set.seed(2025)
n_labeled <- nrow(x_labeled)

train_idx <- sample.int(n_labeled, floor(0.7 * n_labeled))
test_idx  <- setdiff(seq_len(n_labeled), train_idx)

x_train <- x_labeled[train_idx, , drop = FALSE]
x_test  <- x_labeled[test_idx,  , drop = FALSE]

cat(sprintf("[ALL] n_labeled=%d; train=%d; test=%d\n",
            n_labeled, nrow(x_train), nrow(x_test)))

#-------------------------------------------------------------------------------
# 4) Black subgroup test/train sets for subgroup evaluation
#-------------------------------------------------------------------------------

x_train_black <- x_train %>%
  filter(race == "Black or African American")

x_test_black <- x_test %>%
  filter(race == "Black or African American")

cat(sprintf("[Black] train=%d; test=%d\n",
            nrow(x_train_black), nrow(x_test_black)))

#-------------------------------------------------------------------------------
# 5) Optional: Black EHR rows for Black-score SSL training
#-------------------------------------------------------------------------------

idx_ehr <- complete.cases(x[, c("X", "DELTA", "C_ehr", SNP)])

x_ehr <- x[idx_ehr, , drop = FALSE]

x_ehr_black <- x_ehr %>%
  filter(race == "Black or African American")

cat(sprintf("[EHR] all=%d; Black=%d\n",
            nrow(x_ehr), nrow(x_ehr_black)))

#-------------------------------------------------------------------------------
# 6) Save tutorial objects
#-------------------------------------------------------------------------------

out_file <- file.path(proj.dir, paste0("RA_tutorial_x_", version, ".rda"))

save(
  x,
  x_train,
  x_test,
  x_train_black,
  x_test_black,
  x_ehr,
  x_ehr_black,
  SNP,
  version,
  file = out_file
)

cat("[OK] Saved tutorial table and splits ->", out_file, "\n")

# Optional CSVs for inspection / manuscript display
write.csv(x, file.path(data.dir, paste0("RA_tutorial_x_", version, ".csv")),
          row.names = FALSE)

write.csv(head(x, 20),
          file.path(data.dir, paste0("RA_tutorial_x_display_", version, ".csv")),
          row.names = FALSE)