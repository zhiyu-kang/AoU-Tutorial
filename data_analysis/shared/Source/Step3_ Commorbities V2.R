
# ---- Config ----
version    <- "V2_Commorbities"
proj.dir  <- "~/shared/project/"
data.dir  <- file.path(proj.dir, "data")
dir.create(data.dir, recursive = TRUE, showWarnings = FALSE)

library(dplyr)
library(googleCloudStorageR)
library(readr)
library(stringr)
library(tidyr)


# Google Cloud authentication
gcs_auth()

# Read the bucket name from environment variable WORKSPACE_BUCKET
my_bucket <- Sys.getenv("WORKSPACE_BUCKET")

# File to download
name_of_file_in_bucket <- "RA_data_comorbidities.csv"

# Download from GCS
gcs_get_object(
  object_name = paste0("data/", name_of_file_in_bucket),
  bucket      = my_bucket,
  saveToDisk  = name_of_file_in_bucket, overwrite   = TRUE
)

# Confirmation message
print(paste("[INFO]", name_of_file_in_bucket, 
            "is successfully downloaded into your working space"))

RA_cohort<- read.csv(name_of_file_in_bucket)

stopifnot(exists("RA_cohort"))

#===============================================================================
# Directories & setup
#===============================================================================
source.dir <- "~/shared/Source/"
shared.dir <- "~/shared/shared/"
proj.dir   <- "~/shared/project/"

#==============================================================
# Load our cohort with 83 SNPs
#==============================================================

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

# 3) Manually specified Black-specific SNPs
Black_specific_snps <- c(
  "8:128564231:T:C",
  "18:3542249:T:C",
  "18:12880207:A:G",
  "19:35722170:A:G",
  "4:48218822:G:A",
  "9:34710263:G:A",
  "1:2552522:G:A",
  "5:134503843:C:T",
  "15:69699078:G:A",
  "15:90361626:G:A"
)

cat("[INFO] Manually specified Black-specific SNPs:\n")
print(Black_specific_snps)

# 4) Check which manually specified SNPs actually exist as columns in dat_black
missing_black_specific <- setdiff(Black_specific_snps, names(dat_black))

if (length(missing_black_specific) > 0) {
  warning("These Black-specific SNPs are not found in dat_black: ",
          paste(missing_black_specific, collapse = ", "))
}

Black_specific_snps_in_dat <- intersect(Black_specific_snps, names(dat_black))

cat("[INFO] # Black-specific SNPs found in dat_black:",
    length(Black_specific_snps_in_dat), "out of",
    length(Black_specific_snps), "\n")

print(Black_specific_snps_in_dat)

# 5) Combine X* SNPs and manually specified Black-specific SNPs
combined_snp_cols <- union(snp_X_cols, Black_specific_snps_in_dat)

cat("[INFO] Total SNP columns selected (X* + Black-specific SNPs present):",
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







