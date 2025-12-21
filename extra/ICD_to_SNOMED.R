# ==============================================================================
# PheCode to OMOP Standard Concept Mapping (R Version)
# 
# Purpose: Map PheCode-associated ICD codes to OMOP standard concepts
#
# ==============================================================================

# ==============================================================================
# USER CONFIGURATION - MODIFY THIS SECTION
# ==============================================================================

config = list(
  
  # --- Input Files ---
  
  # Path to OMOP vocabulary files directory
  # Should contain DX/CONCEPT.csv and DX/CONCEPT_RELATIONSHIP.csv
  omop_dir = "D:/Rcourse/AoU mapping/",
  
  # PheCode-to-ICD mapping file
  # Expected columns: ICD (code), Flag (9 or 10 for ICD version)
  phecode_file = "Phecode714_1_RA.csv",
  
  # --- Output Files ---
  
  # Output file for concept IDs only (CSV)
  output_csv = "RA_SNOMED_Concepts.csv",
  
  # Output file for full concept details (Excel, set to NULL to skip)
  output_xlsx = "RA_SNOMED_Concepts_Full.xlsx",
  
  # Sheet name for Excel output
  output_sheet = "OMOP_mapping",
  
  # --- Mapping Options ---
  
  # Include hierarchy expansion via "Subsumes" relationship?
  # TRUE  = include all descendant concepts (more inclusive)
  # FALSE = direct mapping only
  expand_hierarchy = TRUE,
  
  # Domain filter (set to NULL to include all domains)
  # Common values: "Condition", "Drug", "Procedure", "Measurement"
  domain_filter = "Condition",
  
  # Standard concept filter
  # "S" = Standard only, "C" = Classification only, c("S","C") = both, NULL = all
  standard_filter = "S"
  
)

# ==============================================================================
# LOAD REQUIRED PACKAGES
# ==============================================================================

# Using openxlsx instead of xlsx (no Java dependency)
if (!require("openxlsx")) {
  install.packages("openxlsx")
  library(openxlsx)
}

# ==============================================================================
# MAIN SCRIPT - NO MODIFICATION NEEDED BELOW
# ==============================================================================

cat("=== PheCode to OMOP Mapping ===\n\n")

# --- Load OMOP Vocabulary ---

cat("Loading OMOP vocabulary files...\n")

omop.dict = read.delim(
  paste0(config$omop_dir, "Dict/CONCEPT.csv"), 
  quote = '', 
  stringsAsFactors = FALSE
)

omop.rel = read.delim(
  paste0(config$omop_dir, "Dict/CONCEPT_RELATIONSHIP.csv"), 
  quote = '', 
  stringsAsFactors = FALSE
)

# Filter relationships
omop.mapsto = omop.rel[omop.rel$relationship_id == "Maps to", ]

if (config$expand_hierarchy) {
  omop.subsumes = omop.rel[omop.rel$relationship_id == "Subsumes", ]
  # Keep only subsumes between standard concepts
  omop.subsumes = omop.subsumes[
    omop.subsumes$concept_id_1 %in% omop.mapsto$concept_id_2 &
      omop.subsumes$concept_id_2 %in% omop.mapsto$concept_id_2, ]
}

rm(omop.rel)  # Free memory

# cat("  - Concepts loaded:", nrow(omop.dict), "\n")
# cat("  - 'Maps to' relationships:", nrow(omop.mapsto), "\n")
# if (config$expand_hierarchy) {
#   cat("  - 'Subsumes' relationships:", nrow(omop.subsumes), "\n")
# }

# --- Load PheCode Mapping ---

phe = read.csv(config$phecode_file, colClasses = "character")

icd9 = unique(phe$ICD[phe$Flag == "9"])
icd10 = unique(phe$ICD[phe$Flag == "10"])

cat("ICD-9 codes:", length(icd9), "\n")
cat("ICD-10 codes:", length(icd10), "\n")

# --- Find ICD Source Concepts ---

icd.concepts = omop.dict[
  (omop.dict$vocabulary_id == "ICD9CM" & omop.dict$concept_code %in% icd9) |
    (omop.dict$vocabulary_id == "ICD10CM" & omop.dict$concept_code %in% icd10), ]

cat("ICD source concepts found:", nrow(icd.concepts), "\n")

# --- Map to Standard Concepts ---

std.ids = unique(omop.mapsto$concept_id_2[
  omop.mapsto$concept_id_1 %in% icd.concepts$concept_id]) # indicator

cat("standard concepts:", length(std.ids), "\n")

# --- Hierarchy Expansion (Optional) ---

if (config$expand_hierarchy && length(std.ids) > 0) {
  cat("\nExpanding hierarchy via 'Subsumes'...\n")
  
  all.ids = std.ids
  current.ids = std.ids
  level = 0
  
  while (length(current.ids) > 0) {
    level = level + 1
    child.ids = omop.subsumes$concept_id_2[
      omop.subsumes$concept_id_1 %in% current.ids]
    child.ids = setdiff(child.ids, all.ids)  # Avoid duplicates
    
    if (length(child.ids) > 0) {
      cat("  - Level", level, ":", length(child.ids), "new concepts\n")
      all.ids = c(all.ids, child.ids)
    }
    current.ids = child.ids
  }
  
  std.ids = unique(all.ids)
  cat("  - Total after expansion:", length(std.ids), "\n")
}

# --- Get Full Concept Details ---

std.concepts = omop.dict[omop.dict$concept_id %in% std.ids, ]

# Apply filters
if (!is.null(config$standard_filter)) {
  std.concepts = std.concepts[
    std.concepts$standard_concept %in% config$standard_filter, ]
}

if (!is.null(config$domain_filter)) {
  std.concepts = std.concepts[
    std.concepts$domain_id %in% config$domain_filter, ]
}

cat("\nFinal standard concepts:", nrow(std.concepts), "\n")

# --- Export Results ---

# CSV with concept IDs only
write.csv(
  data.frame(concept_id = std.concepts$concept_id),
  file = config$output_csv,
  row.names = FALSE
)
cat("  - Saved:", config$output_csv, "\n")

# Excel with full details (optional)
if (!is.null(config$output_xlsx)) {
  write.xlsx(
    std.concepts,
    file = config$output_xlsx,
    sheetName = config$output_sheet,
    rowNames = FALSE
  )
  cat("  - Saved:", config$output_xlsx, "\n")
}