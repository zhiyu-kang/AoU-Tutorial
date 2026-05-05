# ---- Config ----
version    <- "V2_AncestryPCA"
proj.dir  <- "~/shared/project/"
data.dir  <- file.path(proj.dir, "data")
dir.create(data.dir, recursive = TRUE, showWarnings = FALSE)

library(dplyr)
library(googleCloudStorageR)

# Google Cloud authentication
gcs_auth()

# Read the bucket name from environment variable WORKSPACE_BUCKET
my_bucket <- Sys.getenv("WORKSPACE_BUCKET")

#===============================================================================
# 1) Download RA cohort file
#===============================================================================
#V6.5 in workspace
name_of_file_in_bucket <- "RA_data3.csv"

gcs_get_object(
  object_name = paste0("data/", name_of_file_in_bucket),
  bucket      = my_bucket,
  saveToDisk  = file.path(data.dir, name_of_file_in_bucket),
  overwrite   = TRUE
)

print(paste("[INFO]", name_of_file_in_bucket,
            "is successfully downloaded into", data.dir))

RA_cohort <- read.csv(file.path(data.dir, name_of_file_in_bucket))

stopifnot(exists("RA_cohort"))
stopifnot("person_id" %in% names(RA_cohort))

cohort_ids <- as.integer(RA_cohort$person_id)

#===============================================================================
# 2) Download 16 ancestry SNP batch files
#===============================================================================

batch_files <- sprintf("RA_ancestry_SNPs_batch_%02d.csv", 1:16)

for (fname in batch_files) {
  message("[DOWNLOAD] ", fname)
  
  gcs_get_object(
    object_name = paste0("data/", fname),
    bucket      = my_bucket,
    saveToDisk  = file.path(data.dir, fname),
    overwrite   = TRUE
  )
}

print("[INFO] All ancestry SNP batch files downloaded.")

#===============================================================================
# 3) Read each batch, filter to RA cohort, then merge
#===============================================================================

snp_list <- lapply(batch_files, function(fname) {
  fpath <- file.path(data.dir, fname)
  
  message("[READ/FILTER] ", fname)
  
  dat <- read.csv(fpath, check.names = FALSE)
  dat$person_id <- as.integer(dat$person_id)
  
  dat <- dat[dat$person_id %in% cohort_ids, , drop = FALSE]
  
  dat
})

RA_ancestry_SNPs <- Reduce(
  function(x, y) merge(x, y, by = "person_id", all = TRUE),
  snp_list
)

print(dim(RA_ancestry_SNPs))
head(RA_ancestry_SNPs[, 1:min(6, ncol(RA_ancestry_SNPs))])

# Optional save merged SNP matrix
merged_snp_file <- file.path(data.dir, paste0("RA_ancestry_SNPs_merged_", version, ".csv"))
write.csv(RA_ancestry_SNPs, merged_snp_file, row.names = FALSE)

print(paste("[INFO] Merged ancestry SNP matrix saved to:", merged_snp_file))

#===============================================================================
# Create top 5 ancestry PCs from extracted ancestry SNPs
#===============================================================================

# 1) Separate ID and genotype matrix
person_id <- RA_ancestry_SNPs$person_id

G <- RA_ancestry_SNPs[, setdiff(names(RA_ancestry_SNPs), "person_id"), drop = FALSE]

# Make sure all SNP columns are numeric
G <- as.data.frame(lapply(G, as.numeric))

# 2) Remove SNP columns with all missing or zero variance
sds <- apply(G, 2, sd, na.rm = TRUE)

keep_snp <- is.finite(sds) & sds > 0

G <- G[, keep_snp, drop = FALSE]

cat("[INFO] Number of SNP columns used for PCA:", ncol(G), "\n")

# 3) Mean-impute missing genotype dosages
for (j in seq_len(ncol(G))) {
  G[is.na(G[, j]), j] <- mean(G[, j], na.rm = TRUE)
}

# 4) Run PCA on standardized SNP dosage matrix
pca_fit <- prcomp(G, center = TRUE, scale. = TRUE)

# 5) Extract top 5 PCs
ancestry_pcs <- data.frame(
  person_id = person_id,
  Ancestry_PC1 = pca_fit$x[, 1],
  Ancestry_PC2 = pca_fit$x[, 2],
  Ancestry_PC3 = pca_fit$x[, 3],
  Ancestry_PC4 = pca_fit$x[, 4],
  Ancestry_PC5 = pca_fit$x[, 5]
)

head(ancestry_pcs)

# Optional PCA summary
pca_var <- pca_fit$sdev^2
pca_summary <- data.frame(
  PC = paste0("PC", seq_along(pca_var)),
  Eigenvalue = pca_var,
  ProportionVariance = pca_var / sum(pca_var),
  CumulativeVariance = cumsum(pca_var / sum(pca_var))
)

write.csv(
  ancestry_pcs,
  file.path(data.dir, paste0("RA_ancestry_top5_PCs_", version, ".csv")),
  row.names = FALSE
)

write.csv(
  pca_summary,
  file.path(data.dir, paste0("RA_ancestry_PCA_summary_", version, ".csv")),
  row.names = FALSE
)

#-------------------------------------------------------------------------------
# Restrict RA_cohort to participants with ancestry PCs, then attach PCs
#-------------------------------------------------------------------------------

pc_cols <- paste0("Ancestry_PC", 1:5)

# Make sure person_id type matches
RA_cohort$person_id <- as.integer(RA_cohort$person_id)
ancestry_pcs$person_id <- as.integer(ancestry_pcs$person_id)

# Check unique IDs
cat("RA_cohort rows:", nrow(RA_cohort), "\n")
cat("RA_cohort unique IDs:", length(unique(RA_cohort$person_id)), "\n")
cat("ancestry_pcs rows:", nrow(ancestry_pcs), "\n")
cat("ancestry_pcs unique IDs:", length(unique(ancestry_pcs$person_id)), "\n")

# If ancestry_pcs has duplicate person_id, keep one row per person_id
ancestry_pcs <- ancestry_pcs[!duplicated(ancestry_pcs$person_id), ]

# Explicitly filter RA_cohort using ancestry_pcs person_id
RA_cohort <- RA_cohort[RA_cohort$person_id %in% ancestry_pcs$person_id, , drop = FALSE]

cat("[INFO] RA_cohort after filtering by ancestry PC IDs:\n")
print(dim(RA_cohort))

# Now merge PCs onto filtered RA_cohort
RA_cohort <- merge(
  RA_cohort,
  ancestry_pcs,
  by = "person_id",
  all.x = TRUE
)

# Checks
stopifnot(all(pc_cols %in% names(RA_cohort)))
stopifnot(!any(is.na(RA_cohort[, pc_cols])))

cat("[INFO] RA_cohort after adding ancestry PCs:\n")
print(dim(RA_cohort))

#-------------------------------------------------------------------------------
# Deduplicate RA_cohort after adding ancestry PCs
#-------------------------------------------------------------------------------

cat("[BEFORE] RA_cohort rows:", nrow(RA_cohort), "\n")
cat("[BEFORE] unique person_id:", length(unique(RA_cohort$person_id)), "\n")

# Check whether duplicates are exact duplicates
cat("[CHECK] rows after full distinct():", nrow(dplyr::distinct(RA_cohort)), "\n")

# Since duplicated person_id rows appear identical, keep one row per person_id
RA_cohort <- RA_cohort %>%
  arrange(person_id) %>%
  distinct(person_id, .keep_all = TRUE)

cat("[AFTER] RA_cohort rows:", nrow(RA_cohort), "\n")
cat("[AFTER] unique person_id:", length(unique(RA_cohort$person_id)), "\n")

stopifnot(nrow(RA_cohort) == length(unique(RA_cohort$person_id)))
stopifnot(!any(is.na(RA_cohort[, paste0("Ancestry_PC", 1:5)])))


# ---- Genetics columns ----
genetic_cols <- c(
  "12:111446804:T:C", "12:45976333:C:G", "13:39781776:T:C",
  "14:104920174:G:A", "14:68287978:G:A", "1:116738074:C:T",
  "5:143224856:A:G",  "6:159082054:A:G", "6:36414159:G:GA",
  "9:34710263:G:A"
)

genetic_cols_safe <- genetic_cols
pc_cols<-paste0("Ancestry_PC", 1:5)

genetic_cols_safe<-c(genetic_cols_safe,pc_cols)

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
colnames(Z_labeled_mat_all) <- genetic_cols_safe

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
colnames(Z_unlabeled_mat_all) <- genetic_cols_safe

race_unlabeled_all <- unlabeled_all_clean$race

## --- 3) One global train/test split on labeled set -------------------

set.seed(2025)
n_lab         <- nrow(labeled_all)
train_idx_all <- sample.int(n_lab, floor(0.7 * n_lab))   # 50:50 split
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



