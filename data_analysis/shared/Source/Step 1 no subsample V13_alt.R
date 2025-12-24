# ---- Config ----
version    <- "V13_alt"
proj.dir   <- "~/shared/project/"

library(googleCloudStorageR)
library(dplyr)

# Google Cloud authentication
gcs_auth()

# Read the bucket name from environment variable WORKSPACE_BUCKET
my_bucket <- Sys.getenv("WORKSPACE_BUCKET")

# File to download
name_of_file_in_bucket <- "RA_data_map.csv"

# Download from GCS
gcs_get_object(
  object_name = paste0("data/", name_of_file_in_bucket),
  bucket      = my_bucket,
  saveToDisk  = name_of_file_in_bucket, overwrite   = TRUE
)

# Confirmation message
print(paste("[INFO]", name_of_file_in_bucket,
            "is successfully downloaded into your working space"))

RA_full <- read.csv(name_of_file_in_bucket)

#===============================================================================
# Cohort definitions (3 groups)
#===============================================================================

# Group 1: Survey-YES RA  (keep ALL)
RA_yes <- RA_full %>%
  filter(ra_event_survey == 1)

n_yes  <- nrow(RA_yes)
id_yes <- unique(RA_yes$person_id)

cat("[INFO] Survey-YES RA rows: ", n_yes, "\n",
    "[INFO] Survey-YES unique IDs: ", length(id_yes), "\n", sep = "")


# Group 2: RA-code (EHR) but NOT survey-YES (candidate pool; will be subsampled in TRAIN only)
RA_code_only <- RA_full %>%
  filter((is.na(ra_event_survey) | ra_event_survey == 0) &
           (ra_code_YN == 1))

n_code_only  <- nrow(RA_code_only)
id_code_only <- unique(RA_code_only$person_id)

cat("[INFO] RA-code-only rows: ", n_code_only, "\n",
    "[INFO] RA-code-only unique IDs: ", length(id_code_only), "\n", sep = "")


# Group 3: Controls (NOT survey-YES AND NOT RA-code)
RA_control_all <- RA_full %>%
  filter((is.na(ra_event_survey) | ra_event_survey == 0) &
           (is.na(ra_code_YN) | ra_code_YN == 0))

n_control_all  <- nrow(RA_control_all)
id_control_all <- unique(RA_control_all$person_id)

cat("[INFO] Control pool rows: ", n_control_all, "\n",
    "[INFO] Control pool unique IDs: ", length(id_control_all), "\n", sep = "")

#===============================================================================
# Split: 30% test (NO subsampling) + 70% train (then subsample within train)
#   NOTE: This split is PERSON-level to avoid leakage.
#===============================================================================

set.seed(123)

all_ids <- unique(RA_full$person_id)
n_ids   <- length(all_ids)

test_ids  <- sample(all_ids, size = ceiling(0.30 * n_ids), replace = FALSE)
train_ids <- setdiff(all_ids, test_ids)

cat("[INFO] Total unique IDs: ", n_ids, "\n",
    "[INFO] Train unique IDs: ", length(train_ids), "\n",
    "[INFO] Test unique IDs:  ", length(test_ids), "\n", sep = "")

# Test set: take all rows for those people (no subsampling)
RA_test <- RA_full %>%
  filter(person_id %in% test_ids)

# Train full pool: take all rows for those people
RA_train_full <- RA_full %>%
  filter(person_id %in% train_ids)

cat("[INFO] Train FULL rows (pre-subsample): ", nrow(RA_train_full), "\n",
    "[INFO] Test rows (no subsample):        ", nrow(RA_test), "\n", sep = "")

#===============================================================================
# Training subsampling by 3 groups + weights
#   - keep ALL survey-YES
#   - subsample RA-code-only
#   - subsample controls
#===============================================================================

# ---- choose your keep rates (edit these) ----
p_keep_code    <- 0.30  # keep 30% of RA-code-only in TRAIN
p_keep_control <- 0.08  # keep 8% of controls in TRAIN (matches your earlier style)

# Train group 1: keep all survey-YES
train_yes <- RA_train_full %>% filter(ra_event_survey == 1)

# Train group 2: RA-code-only (subsample)
train_code_pool <- RA_train_full %>%
  filter((is.na(ra_event_survey) | ra_event_survey == 0) &
           (ra_code_YN == 1))

set.seed(456)
n_code_keep <- round(p_keep_code * nrow(train_code_pool))

train_code_sub <- train_code_pool %>%
  sample_n(n_code_keep)

# Train group 3: controls (subsample)
train_ctrl_pool <- RA_train_full %>%
  filter((is.na(ra_event_survey) | ra_event_survey == 0) &
           (is.na(ra_code_YN) | ra_code_YN == 0))

set.seed(789)
n_ctrl_keep <- round(p_keep_control * nrow(train_ctrl_pool))

train_ctrl_sub <- train_ctrl_pool %>%
  sample_n(n_ctrl_keep)

# Combine training analysis set
RA_train <- bind_rows(train_yes, train_code_sub, train_ctrl_sub)

# Add weight column
RA_train <- RA_train %>%
  mutate(
    weight = case_when(
      ra_event_survey == 1 ~ 1,
      ( (is.na(ra_event_survey) | ra_event_survey == 0) & (ra_code_YN == 1) ) ~ 1 / p_keep_code,
      ( (is.na(ra_event_survey) | ra_event_survey == 0) & (is.na(ra_code_YN) | ra_code_YN == 0) ) ~ 1 / p_keep_control,
      TRUE ~ NA_real_
    )
  )

# Test weights are 1 (no subsampling)
RA_test <- RA_test %>%
  mutate(weight = 1)

if (any(is.na(RA_train$weight))) {
  stop("[ERROR] NA weights found in RA_train. Check cohort logic.")
}

cat("[INFO] Train YES rows kept:          ", nrow(train_yes), "\n",
    "[INFO] Train RA-code pool rows:      ", nrow(train_code_pool), "\n",
    "[INFO] Train RA-code rows kept:      ", nrow(train_code_sub), " (p=", p_keep_code, ")\n",
    "[INFO] Train Control pool rows:      ", nrow(train_ctrl_pool), "\n",
    "[INFO] Train Control rows kept:      ", nrow(train_ctrl_sub), " (p=", p_keep_control, ")\n",
    "[INFO] Final TRAIN rows:             ", nrow(RA_train), "\n",
    "[INFO] Final TEST rows (no subsamp): ", nrow(RA_test), "\n", sep = "")

#===============================================================================
# Model input prep: labeled/unlabeled + Black subsets
#===============================================================================

genetic_cols <- c(
  "X12.111446804.T.C", "X12.45976333.C.G", "X13.39781776.T.C",
  "X14.104920174.G.A", "X14.68287978.G.A", "X1.116738074.C.T",
  "X5.143224856.A.G",  "X6.159082054.A.G", "X6.36414159.G.GA",
  "X9.34710263.G.A"
)

genetic_cols_safe <- make.names(genetic_cols)

stopifnot(all(genetic_cols_safe %in% names(RA_train)))
stopifnot(all(genetic_cols_safe %in% names(RA_test)))


# ---- Labeled TRAIN (survey observed) ----
need_cols_lab <- c("age_at_survey_event", "ra_event_survey", "race", "person_id",
                   genetic_cols_safe, "weight")

idx_lab_tr <- complete.cases(RA_train[, need_cols_lab])
labeled_tr_clean <- RA_train[idx_lab_tr, , drop = FALSE]

labeled_tr <- data.frame(
  C     = labeled_tr_clean$age_at_survey_event,
  delta = labeled_tr_clean$ra_event_survey
)

Z_labeled_tr <- as.matrix(labeled_tr_clean[, genetic_cols_safe, drop = FALSE])
storage.mode(Z_labeled_tr) <- "numeric"
colnames(Z_labeled_tr) <- genetic_cols

V_labeled_tr <- labeled_tr_clean$weight
race_labeled_tr <- labeled_tr_clean$race
id_labeled_tr <- labeled_tr_clean$person_id

cat("[INFO] Labeled TRAIN rows: ", nrow(labeled_tr), "\n", sep = "")


# ---- Labeled TEST (survey observed) ----
idx_lab_te <- complete.cases(RA_test[, need_cols_lab])
labeled_te_clean <- RA_test[idx_lab_te, , drop = FALSE]

labeled_te <- data.frame(
  C     = labeled_te_clean$age_at_survey_event,
  delta = labeled_te_clean$ra_event_survey
)

Z_labeled_te <- as.matrix(labeled_te_clean[, genetic_cols_safe, drop = FALSE])
storage.mode(Z_labeled_te) <- "numeric"
colnames(Z_labeled_te) <- genetic_cols

V_labeled_te <- labeled_te_clean$weight   # will be 1’s
race_labeled_te <- labeled_te_clean$race
id_labeled_te <- labeled_te_clean$person_id

cat("[INFO] Labeled TEST rows:  ", nrow(labeled_te), "\n", sep = "")


# ---- Unlabeled TRAIN (EHR observed) ----
need_cols_unlab <- c("age_at_condition_event", "ra_code_YN", "age_at_last_ehr",
                     "race", "person_id", genetic_cols_safe, "weight")

idx_unlab_tr <- complete.cases(RA_train[, need_cols_unlab])
unlabeled_tr_clean <- RA_train[idx_unlab_tr, , drop = FALSE]

unlabeled_tr <- data.frame(
  X     = unlabeled_tr_clean$age_at_condition_event,
  DELTA = unlabeled_tr_clean$ra_code_YN,
  C     = unlabeled_tr_clean$age_at_last_ehr
)

Z_unlabeled_tr <- as.matrix(unlabeled_tr_clean[, genetic_cols_safe, drop = FALSE])
storage.mode(Z_unlabeled_tr) <- "numeric"
colnames(Z_unlabeled_tr) <- genetic_cols

V_unlabeled_tr <- unlabeled_tr_clean$weight
race_unlabeled_tr <- unlabeled_tr_clean$race
id_unlabeled_tr <- unlabeled_tr_clean$person_id

cat("[INFO] Unlabeled TRAIN rows: ", nrow(unlabeled_tr), "\n", sep = "")





is_black <- function(x) x == "Black or African American"

# Labeled Black
blk_lab_tr <- is_black(race_labeled_tr)
blk_lab_te <- is_black(race_labeled_te)

label_split_black <- list(
  train = list(labeled_data = labeled_tr[blk_lab_tr, , drop = FALSE],
               Z           = Z_labeled_tr[blk_lab_tr, , drop = FALSE],
               V           = V_labeled_tr[blk_lab_tr],
               id          = id_labeled_tr[blk_lab_tr]),
  test  = list(labeled_data = labeled_te[blk_lab_te, , drop = FALSE],
               Z           = Z_labeled_te[blk_lab_te, , drop = FALSE],
               V           = V_labeled_te[blk_lab_te],
               id          = id_labeled_te[blk_lab_te])
)

cat("[INFO] Black labeled: train=", nrow(label_split_black$train$labeled_data),
    ", test=", nrow(label_split_black$test$labeled_data), "\n", sep = "")

# Unlabeled Black
blk_unlab_tr <- is_black(race_unlabeled_tr)


unlab_split_black <- list(
  train = list(
    unlabeled_data = unlabeled_tr[blk_unlab_tr, , drop = FALSE],
    Z             = Z_unlabeled_tr[blk_unlab_tr, , drop = FALSE],
    V             = V_unlabeled_tr[blk_unlab_tr],
    id            = id_unlabeled_tr[blk_unlab_tr]
  )
)

cat("[INFO] Black unlabeled: train=", nrow(unlab_split_black$train$unlabeled_data),
    " (no unlabeled test)\n", sep = "")



#===============================================================================
# Save objects
#===============================================================================

if (!dir.exists(proj.dir)) {
  dir.create(proj.dir, recursive = TRUE)
}

save_path <- file.path(proj.dir, paste0("case_control_alt_", version, ".RData"))

# Person-level IDs
id_train <- unique(RA_train$person_id)
id_test  <- unique(RA_test$person_id)

# (Optional) convenience IDs for labeled/unlabeled subsets
id_labeled_train   <- unique(id_labeled_tr)
id_labeled_test    <- unique(id_labeled_te)
id_unlabeled_train <- unique(id_unlabeled_tr)

# Save everything needed downstream
save(
  # ---- raw / cohort objects ----
  RA_full,
  RA_train_full,
  RA_train,
  RA_test,
  id_train,
  id_test,
  p_keep_code,
  p_keep_control,
  
  # ---- genetics metadata ----
  genetic_cols,
  genetic_cols_safe,
  
  # ---- labeled bundles ----
  labeled_tr, Z_labeled_tr, V_labeled_tr, race_labeled_tr, id_labeled_tr,
  labeled_te, Z_labeled_te, V_labeled_te, race_labeled_te, id_labeled_te,
  
  # ---- unlabeled bundles ----
  unlabeled_tr, Z_unlabeled_tr, V_unlabeled_tr, race_unlabeled_tr, id_unlabeled_tr,
  
  # ---- Black subsets ----
  label_split_black,
  unlab_split_black,
  
  # ---- convenience ID sets ----
  id_labeled_train,
  id_labeled_test,
  id_unlabeled_train,

  
  file = save_path
)

cat(
  "\n[INFO] Saved alternative-analysis objects to:\n",
  "   ", save_path, "\n\n",
  "[INFO] Summary of saved objects:\n",
  "   Train rows (subsampled):        ", nrow(RA_train), "\n",
  "   Test rows (no subsample):       ", nrow(RA_test), "\n",
  "   Unique train IDs:               ", length(id_train), "\n",
  "   Unique test IDs:                ", length(id_test), "\n",
  "   p_keep_code (train):            ", p_keep_code, "\n",
  "   p_keep_control (train):         ", p_keep_control, "\n\n",
  "   Labeled TRAIN rows:             ", nrow(labeled_tr), "\n",
  "   Labeled TEST rows:              ", nrow(labeled_te), "\n",
  "   Unlabeled TRAIN rows:           ", nrow(unlabeled_tr), "\n",
  "   Black labeled TRAIN rows:       ", nrow(label_split_black$train$labeled_data), "\n",
  "   Black labeled TEST rows:        ", nrow(label_split_black$test$labeled_data), "\n",
  "   Black unlabeled TRAIN rows:     ", nrow(unlab_split_black$train$unlabeled_data), "\n",
  sep = ""
)

