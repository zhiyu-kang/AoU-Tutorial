library(readr)
library(dplyr)
library(stringr)
library(tidyr)

version <- "V13_alt"

#===============================================================================
# Directories & setup
#===============================================================================
proj.dir <- "~/shared/project/"

#==============================================================
# 0) Load V13_alt saved objects (already has train/test + Black split IDs)
#==============================================================
load(file.path(proj.dir, paste0("case_control_alt_", version, ".RData")))

stopifnot(exists("label_split_black"))
stopifnot(exists("unlab_split_black"))

#==============================================================
# 1) Load SNP83 dosage table + normalize person_id type
#==============================================================
snp83 <- read_csv("RA_wgs_83.csv",
                  name_repair = "minimal",
                  col_types   = cols(.default = col_double(),
                                     person_id = col_character()))

# We'll join SNPs to RA_full (or RA_train/RA_test). Use RA_full so we can subset by IDs later.
RA_full2 <- RA_full %>% mutate(person_id = as.character(person_id))
snp83    <- snp83    %>% mutate(person_id = as.character(person_id))

dat <- RA_full2 %>% left_join(snp83, by = "person_id")

missing_in_snp <- anti_join(RA_full2 %>% distinct(person_id),
                            snp83 %>% select(person_id),
                            by = "person_id")

message("Rows in RA_full: ", nrow(RA_full2),
        " | Rows after join: ", nrow(dat),
        " | RA_full IDs without SNPs: ", nrow(missing_in_snp))

#============================================================
# 2) Load literature OR file and normalize variant IDs
#============================================================
norm_id <- function(x) {
  x %>%
    str_trim() %>%
    str_replace(regex("^chr", ignore_case = TRUE), "") %>%
    str_replace_all("-", ":") %>%
    toupper()
}

or <- read_csv("ALL_ST4_plus_ST5X_GRCh38.csv",
               name_repair = "minimal",
               show_col_types = FALSE) %>%
  mutate(variant_id38_norm = norm_id(variant_id38))

or_dedup <- or %>%
  filter(!is.na(variant_id38_norm)) %>%
  distinct(variant_id38_norm, .keep_all = TRUE)

#============================================================
# 3) Define BLACK TRAINING IDs (NO leakage)
#    Use labeled + unlabeled Black training IDs
#============================================================
id_black_tr_lab   <- as.character(label_split_black$train$id)
id_black_tr_unlab <- as.character(unlab_split_black$train$id)

id_black_train <- union(id_black_tr_lab, id_black_tr_unlab)
cat("[INFO] Black training unique IDs (lab ∪ unlab): ", length(id_black_train), "\n", sep = "")

dat_black_train <- dat %>%
  filter(person_id %in% id_black_train)

cat("[INFO] Black training rows after join: ", nrow(dat_black_train), "\n", sep = "")

#============================================================
# 4) AF/MAF computation on BLACK TRAINING ONLY
#============================================================
snp_cols <- setdiff(names(snp83), "person_id")

af_black_tr <- dat_black_train %>%
  select(person_id, all_of(snp_cols)) %>%
  pivot_longer(
    cols      = all_of(snp_cols),
    names_to  = "snp_id",
    values_to = "geno"
  ) %>%
  group_by(snp_id) %>%
  summarise(
    N_called  = sum(!is.na(geno)),
    call_rate = N_called / nrow(dat_black_train),
    AF        = mean(geno, na.rm = TRUE) / 2,
    .groups   = "drop"
  ) %>%
  mutate(
    snp_id_norm = norm_id(snp_id),
    MAF_hat     = pmin(AF, 1 - AF)
  )

# Join to OR table
merged_tr <- af_black_tr %>%
  inner_join(or_dedup, by = c("snp_id_norm" = "variant_id38_norm")) %>%
  mutate(
    OR_num = suppressWarnings(as.numeric(OR)),
    OR_max = if_else(is.finite(OR_num) & OR_num > 0, pmax(OR_num, 1 / OR_num), NA_real_),
    score  = OR_max * MAF_hat
  ) %>%
  filter(!is.na(score))

cat("[INFO] AF rows (Black train): ", nrow(af_black_tr),
    " | OR rows: ", nrow(or_dedup),
    " | matched: ", nrow(merged_tr), "\n", sep = "")

#============================================================
# 5) Pick TOP-K SNPs (from BLACK TRAINING ranking)
#    Add basic QC if you want (recommended)
#============================================================
K <- 10
call_rate_min <- 0.95
maf_min <- 0.01

topK_black <- merged_tr %>%
  filter(call_rate >= call_rate_min, MAF_hat >= maf_min) %>%
  arrange(desc(score)) %>%
  select(snp_id, snp_id_norm, OR, OR_max, AF, MAF_hat, score, call_rate, N_called, variant_id38) %>%
  slice_head(n = K)

print(topK_black)

topK_snps <- topK_black %>% pull(snp_id)

cat("[INFO] Top-", K, " Black TRAIN SNPs:\n", sep = "")
print(topK_snps)

# Save the ranking table and SNP list
write_csv(topK_black, file.path(proj.dir, paste0("BlackTrain_Top", K, "_SNPs_", version, ".csv")))
write_lines(topK_snps, file.path(proj.dir, paste0("BlackTrain_Top", K, "_SNPs_", version, ".txt")))

#============================================================
# Output: keep ONLY covariates + old SNPs (X*) + 10 NEW SNPs
#   - 3 files: Black train labeled, Black test labeled, Black train unlabeled
#============================================================

# ---- covariates (your old set) ----
covariate_cols <- c(
  "person_id",
  "gender",
  "date_of_birth",
  "race",
  "ethnicity",
  "sex_at_birth",
  "survey_datetime",
  "answer",
  "condition_start_datetime",
  "condition_start_datetime_ehr",
  "ra_code_YN",
  "ra_event_survey",
  "age_at_survey_event",
  "age_at_condition_event",
  "age_at_last_ehr"
)

# ---- old SNPs = X* columns ----
snp_X_cols <- grep("^X", names(dat), value = TRUE)

# ---- new SNPs = topK_snps (length 10), but remove overlaps vs X* by normalized ID ----
norm_id <- function(x) {
  x %>%
    stringr::str_trim() %>%
    stringr::str_replace(stringr::regex("^chr", ignore_case = TRUE), "") %>%
    stringr::str_replace_all("-", ":") %>%
    toupper()
}
x_to_norm <- function(xname) {
  xname %>%
    stringr::str_replace("^X", "") %>%
    stringr::str_replace_all("\\.", ":") %>%
    norm_id()
}

stopifnot(exists("topK_snps"))
stopifnot(length(topK_snps) >= 10)

top10_new <- topK_snps[1:10]

x_norm    <- x_to_norm(snp_X_cols)
top_norm  <- norm_id(top10_new)

top10_new_nodup <- top10_new[ !(top_norm %in% x_norm) ]
top10_new_in_dat <- intersect(top10_new_nodup, names(dat))

# ---- final kept SNPs ----
keep_snp_cols <- unique(c(snp_X_cols, top10_new_in_dat))

cat("[INFO] Old X* SNPs: ", length(snp_X_cols), "\n", sep = "")
cat("[INFO] New SNPs requested (10): ", length(top10_new), "\n", sep = "")
cat("[INFO] New SNPs after de-dup vs X*: ", length(top10_new_nodup), "\n", sep = "")
cat("[INFO] New SNPs present in dat: ", length(top10_new_in_dat), "\n", sep = "")
cat("[INFO] Total SNP cols kept (old + new): ", length(keep_snp_cols), "\n", sep = "")

# ---- IDs (no unlabeled test) ----
id_blk_tr_lab   <- as.character(label_split_black$train$id)
id_blk_te_lab   <- as.character(label_split_black$test$id)
id_blk_tr_unlab <- as.character(unlab_split_black$train$id)

# ---- subset rows ----
dat_blk_tr_lab   <- dat %>% filter(person_id %in% id_blk_tr_lab)
dat_blk_te_lab   <- dat %>% filter(person_id %in% id_blk_te_lab)
dat_blk_tr_unlab <- dat %>% filter(person_id %in% id_blk_tr_unlab)

# ---- select columns: ONLY covariates + old SNPs + new SNPs ----
sel_cols <- c(covariate_cols, keep_snp_cols)
sel_cols <- intersect(sel_cols, names(dat))  # safety

blk_tr_lab_sel   <- dat_blk_tr_lab   %>% dplyr::select(dplyr::all_of(sel_cols))
blk_te_lab_sel   <- dat_blk_te_lab   %>% dplyr::select(dplyr::all_of(sel_cols))
blk_tr_unlab_sel <- dat_blk_tr_unlab %>% dplyr::select(dplyr::all_of(sel_cols))

# ---- save ----
out_tr_lab   <- file.path(proj.dir, paste0("RA_Black_TRAIN_LABELED_oldCov_oldSNP_plusNew10_", version, ".csv"))
out_te_lab   <- file.path(proj.dir, paste0("RA_Black_TEST_LABELED_oldCov_oldSNP_plusNew10_",  version, ".csv"))
out_tr_unlab <- file.path(proj.dir, paste0("RA_Black_TRAIN_UNLABELED_oldCov_oldSNP_plusNew10_", version, ".csv"))

readr::write_csv(blk_tr_lab_sel,   out_tr_lab)
readr::write_csv(blk_te_lab_sel,   out_te_lab)
readr::write_csv(blk_tr_unlab_sel, out_tr_unlab)

cat("[INFO] Saved Black TRAIN labeled:   ", out_tr_lab,   "\n", sep = "")
cat("[INFO] Saved Black TEST labeled:    ", out_te_lab,   "\n", sep = "")
cat("[INFO] Saved Black TRAIN unlabeled: ", out_tr_unlab, "\n", sep = "")

cat("[INFO] Rows: TR_lab=", nrow(blk_tr_lab_sel),
    ", TE_lab=", nrow(blk_te_lab_sel),
    ", TR_unlab=", nrow(blk_tr_unlab_sel), "\n", sep = "")
