library(readr)
library(dplyr)
library(stringr)
library(tidyr)

version <- "V12"
#===============================================================================
# Directories & setup
#===============================================================================
source.dir <- "~/shared/Source/"
shared.dir <- "~/shared/shared/"
proj.dir   <- "~/shared/project/"

#==============================================================
# Load our cohort with 83 SNPs
#==============================================================
load("~/shared/project/case_control_V12.RData")
snp83 <- read_csv("RA_wgs_83.csv",
                  name_repair = "minimal",
                  col_types   = cols(.default = col_double(),
                                     person_id = col_character()))
ra_newest <- RA_cohort %>%
  mutate(person_id = as.character(person_id))

# Join while preserving RA_Newest row order and columns
dat <- ra_newest %>% left_join(snp83, by = "person_id")

# Who's missing SNPs?
missing_in_snp <- anti_join(ra_newest %>% distinct(person_id),
                            snp83 %>% select(person_id),
                            by = "person_id")
message("Rows in RA_Newest: ", nrow(ra_newest),
        " | Rows after join: ", nrow(dat),
        " | RA_Newest IDs without SNPs: ", nrow(missing_in_snp))

# Final save inside project directory, with version tag
out_csv <- file.path(proj.dir, paste0("RA_cohort_with_83SNPs_", version, ".csv"))

write_csv(dat, out_csv)

cat("[INFO] Saved joined cohort + 83 SNPs to:\n", out_csv, "\n")

#============================================================
# Load Previous Literature's File
#============================================================
# --- helper to normalize IDs like "chr1-123:A-G" -> "1:123:A:G"
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

dat_black <- dat %>%
  filter(race == "Black or African American")

# Check how many Black 
nrow(dat_black)


# SNP columns = all SNP columns from snp83 except person_id
snp_cols <- setdiff(names(snp83), "person_id")

# Compute AF for each SNP in the Black cohort
af_black_dat <- dat_black %>%
  select(person_id, all_of(snp_cols)) %>%
  pivot_longer(
    cols      = all_of(snp_cols),
    names_to  = "snp_id",   # SNP name = column name
    values_to = "geno"      # 0/1/2 dosage
  ) %>%
  group_by(snp_id) %>%
  summarise(
    N_called  = sum(!is.na(geno)),
    call_rate = N_called / nrow(dat_black),
    AF        = mean(geno, na.rm = TRUE) / 2,  # AF_alt = E(geno)/2
    .groups   = "drop"
  ) %>%
  mutate(
    snp_id_norm = norm_id(snp_id)
  )

or_dedup <- or %>%
  filter(!is.na(variant_id38_norm)) %>%
  distinct(variant_id38_norm, .keep_all = TRUE)

# 3) Exact join: snp_id (AF) ↔ variant_id38 (OR)
merged <- af_black_dat %>%
  inner_join(or_dedup, by = c("snp_id_norm" = "variant_id38_norm")) %>%
  mutate(
    OR_num = as.numeric(OR),
    OR_max = if_else(is.finite(OR_num) & OR_num > 0,
                     pmax(OR_num, 1 / OR_num),
                     NA_real_)
  )

cat(
  "AF rows (Black from dat):", nrow(af_black_dat),
  "| OR rows:", nrow(or_dedup),
  "| matched:", nrow(merged), "\n"
)


top10_or_MAF <- merged %>%
  mutate(
    OR_num  = as.numeric(OR),
    OR_max  = if_else(is.finite(OR_num) & OR_num > 0,
                      pmax(OR_num, 1 / OR_num),
                      NA_real_),
    MAF_hat = pmin(AF, 1 - AF),    # minor allele freq in your Black cohort
    score   = OR_max * MAF_hat
  ) %>%
  arrange(desc(score)) %>%
  select(
    snp_id, OR, OR_max,
    AF, MAF_hat,
    score, call_rate, N_called, variant_id38
  ) %>%
  slice_head(n = 10)

head(top10_or_MAF, 10)

#============================================================
# Black cohort + covariates + X* SNPs + top-10 score SNPs
#============================================================

# 1) Covariates to keep (as in your screenshot)
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

# 2) SNP columns that start with "X" (original 10 SNPs)
snp_X_cols <- grep("^X", names(dat_black), value = TRUE)

cat("[INFO] # of X* SNP columns in dat_black:", length(snp_X_cols), "\n")
print(snp_X_cols)

# 3) Top-10 SNPs from score ranking
top10_snps <- top15_or_MAF %>%
  slice_head(n = 10) %>%
  pull(snp_id)

cat("[INFO] Top-10 score SNPs:\n")
print(top10_snps)

# 4) Check which top-10 SNPs actually exist as columns in dat_black
missing_top10 <- setdiff(top10_snps, names(dat_black))
if (length(missing_top10) > 0) {
  warning("These top-10 SNPs are not found in dat_black: ",
          paste(missing_top10, collapse = ", "))
}

top10_snps_in_dat <- intersect(top10_snps, names(dat_black))

# 5) Combine X* SNPs and top-10 SNPs
combined_snp_cols <- union(snp_X_cols, top10_snps_in_dat)

cat("[INFO] Total SNP columns selected (X* + top-10 present):",
    length(combined_snp_cols), "\n")

# 6) Subset Black cohort to covariates + combined SNPs
dat_black_selected <- dat_black %>%
  dplyr::select(
    dplyr::all_of(covariate_cols),
    dplyr::all_of(combined_snp_cols)
  )

# 7) Save to project directory with version tag
out_black_selected <- file.path(
  proj.dir,
  paste0("RA_Black_covariates_X10_plusTop10SNPs_", version, ".csv")
)

write_csv(dat_black_selected, out_black_selected)

cat("[INFO] Saved Black cohort (covariates + X* SNPs + top-10 score SNPs) to:\n",
    out_black_selected, "\n")







