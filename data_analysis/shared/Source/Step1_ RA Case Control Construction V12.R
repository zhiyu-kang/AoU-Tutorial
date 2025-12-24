# ---- Config ----
version    <- "V12"
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

RA_full<- read.csv(name_of_file_in_bucket)

# Case Cohort: Who answered YES to the RA questionnaire?
RA_case <- subset(RA_full, ra_event_survey == 1)

n_case  <- nrow(RA_case)
id_case <- unique(RA_case$person_id)
length(id_case)


# Control Cohort: 
RA_control <- RA_full %>%
  filter(
    # keep if NOT survey-yes  OR  NOT EHR-yes
    (is.na(ra_event_survey) | ra_event_survey == 0) |
      (is.na(ra_code_YN) | ra_code_YN == 0)
  )
n_control<-nrow(RA_control)   
id_control <- unique(RA_control$person_id)
length(id_control)

# 8% subsample of control cohort (this will be the FINAL control set)
set.seed(123)

n_sub_control  <- round(0.08 * n_control)   

RA_control_sub <- RA_control %>%
  sample_n(n_sub_control)

nrow(RA_control_sub)

# Get the subsampled control IDs
id_control_sub <- unique(RA_control_sub$person_id)
length(id_control_sub)

RA_cohort<-rbind(RA_case,RA_control_sub)
id_cohort<-unique(RA_cohort$person_id)
length(id_cohort)

# ---- Save case–control objects into one file  ----

if (!dir.exists(proj.dir)) {
  dir.create(proj.dir, recursive = TRUE)
}

save_path <- file.path(proj.dir, paste0("case_control_", version, ".RData"))

save(
  id_case,
  id_control_sub,
  id_cohort,
  RA_case,
  RA_control_sub,
  RA_cohort,
  file = save_path
)

cat(
  "\n[INFO] Saved case–control data objects to:\n",
  "   ", save_path, "\n\n",
  "[INFO] Summary of saved objects:\n",
  "   Cases (RA_case):              ", nrow(RA_case), "\n",
  "   Subsampled controls:          ", nrow(RA_control_sub), "\n",
  "   Total RA_cohort (case+ctrl):  ", nrow(RA_cohort), "\n",
  "   Unique case IDs:              ", length(id_case), "\n",
  "   Unique control subgroup IDs:  ", length(id_control_sub), "\n\n",
  sep = ""
)


