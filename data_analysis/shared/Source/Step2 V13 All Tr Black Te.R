# ---- Config ----
version   <- "V13"
proj.dir  <- "~/shared/project/"
data.dir  <- file.path(proj.dir, "data")
dir.create(data.dir, recursive = TRUE, showWarnings = FALSE)

library(dplyr)

stopifnot(exists("RA_cohort"))

# ---- Genetics columns ----
genetic_cols <- c(
  "X12.111446804.T.C", "X12.45976333.C.G", "X13.39781776.T.C",
  "X14.104920174.G.A", "X14.68287978.G.A", "X1.116738074.C.T",
  "X5.143224856.A.G",  "X6.159082054.A.G", "X6.36414159.G.GA",
  "X9.34710263.G.A"
)

genetic_cols_safe <- make.names(genetic_cols)

stopifnot(all(genetic_cols %in% names(RA_cohort)))


## --- 1) Labeled set = RA_case only -----------------------------------
need_cols_lab_safe <- c("age_at_survey_event", "ra_event_survey", genetic_cols_safe)
idx_lab_all        <- complete.cases(RA_cohort[, need_cols_lab_safe])

labeled_all_clean <- RA_cohort[idx_lab_all, , drop = FALSE]
id_labeled_all <- labeled_all_clean$person_id
labeled_all <- data.frame(
  C     = labeled_all_clean$age_at_survey_event,
  delta = labeled_all_clean$ra_event_survey
)
race_labeled_all <- labeled_all_clean$race

Z_labeled_mat_all <- as.matrix(labeled_all_clean[, genetic_cols_safe, drop = FALSE])
storage.mode(Z_labeled_mat_all) <- "numeric"
colnames(Z_labeled_mat_all) <- genetic_cols

## --- 2) Unlabeled set = RA_control_sub only --------------------------
need_cols_unlab_safe <- c("age_at_condition_event", "ra_code_YN",
                          "age_at_last_ehr", genetic_cols_safe)
idx_unlab_all        <- complete.cases(RA_cohort[, need_cols_unlab_safe])

unlabeled_all_clean <- RA_cohort[idx_unlab_all, , drop = FALSE]
id_unlabeled_all <- unlabeled_all_clean$person_id
unlabeled_all <- data.frame(
  X     = unlabeled_all_clean$age_at_condition_event,
  DELTA = unlabeled_all_clean$ra_code_YN,
  C     = unlabeled_all_clean$age_at_last_ehr
)

Z_unlabeled_mat_all <- as.matrix(unlabeled_all_clean[, genetic_cols_safe, drop = FALSE])
storage.mode(Z_unlabeled_mat_all) <- "numeric"
colnames(Z_unlabeled_mat_all) <- genetic_cols

race_unlabeled_all <- unlabeled_all_clean$race

## --- 3) One global train/test split on labeled set -------------------

set.seed(2025)
n_lab         <- nrow(labeled_all)
train_idx_all <- sample.int(n_lab, floor(0.5 * n_lab))   # 70/30 split
test_idx_all  <- setdiff(seq_len(n_lab), train_idx_all)

label_split_all <- list(
  train = list(
    labeled_data = labeled_all[train_idx_all, , drop = FALSE],
    Z            = Z_labeled_mat_all[train_idx_all, , drop = FALSE],
    race         = race_labeled_all[train_idx_all],
    id           = id_labeled_all[train_idx_all]
  ),
  test = list(
    labeled_data = labeled_all[test_idx_all, , drop = FALSE],
    Z            = Z_labeled_mat_all[test_idx_all, , drop = FALSE],
    race         = race_labeled_all[test_idx_all],
    id           = id_labeled_all[test_idx_all] 
  )
)

cat(sprintf("[ALL] n_labeled=%d (train=%d, test=%d)\n",
            n_lab, length(train_idx_all), length(test_idx_all)))


## --- 4) Black subgroup FROM labeled set ------------------------------

is_black_tr <- label_split_all$train$race == "Black or African American"
is_black_te <- label_split_all$test$race  == "Black or African American"

label_split_black <- list(
  train = list(
    labeled_data = label_split_all$train$labeled_data[is_black_tr, , drop = FALSE],
    Z            = label_split_all$train$Z[is_black_tr, , drop = FALSE],
    id           = label_split_all$train$id[is_black_tr]
  ),
  test = list(
    labeled_data = label_split_all$test$labeled_data[is_black_te, , drop = FALSE],
    Z            = label_split_all$test$Z[is_black_te, , drop = FALSE],
    id           = label_split_all$test$id[is_black_te] 
  )
)

cat(sprintf("[Black] n_labeled=%d\n",
            nrow(label_split_black$train$labeled_data) +
              nrow(label_split_black$test$labeled_data)))
# explicit ID vectors for convenience
id_black_tr  <- label_split_black$train$id                 
id_black_te  <- label_split_black$test$id                  

## --- 5) Black-only UNLABELED subset ---------------------------------

is_black_unlab        <- race_unlabeled_all == "Black or African American"
unlabeled.black       <- unlabeled_all[is_black_unlab, , drop = FALSE]
Z_unlabeled_mat_black <- Z_unlabeled_mat_all[is_black_unlab, , drop = FALSE]
id_black_unlab <- id_unlabeled_all[is_black_unlab]   
cat(sprintf("[Black] n_unlabeled=%d\n", nrow(unlabeled.black)))


## --- 6) Save bundles -------------------------------------------------

prepared_rda_all <- file.path(proj.dir, paste0("RA_model_inputs_", version, ".rda"))
save(labeled_all, Z_labeled_mat_all,
     unlabeled_all, Z_unlabeled_mat_all,
     race_labeled_all, race_unlabeled_all,
     genetic_cols_safe, idx_lab_all, idx_unlab_all,
     train_idx_all, test_idx_all, label_split_all,id_labeled_all, id_unlabeled_all,
     file = prepared_rda_all)
cat("[OK] Saved ALL model inputs →", prepared_rda_all, "\n")

prepared_rda_black <- file.path(proj.dir, paste0("RA_model_inputs_Black_", version, ".rda"))
save(label_split_black,
     unlabeled.black, Z_unlabeled_mat_black,
     genetic_cols_safe,id_black_tr, id_black_te, id_black_unlab,
     file = prepared_rda_black)
cat("[OK] Saved BLACK model inputs →", prepared_rda_black, "\n")



