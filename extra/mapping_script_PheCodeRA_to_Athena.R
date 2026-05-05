
# PheCode 714.1 dictionary for RA
# Downloaded from the PheWAS catalog website

phecode.list = read.csv("Phecode714_1_RA.csv",
                        stringsAsFactors = FALSE)
phecode.list$concept_full = paste0(
  "ICD", phecode.list$Flag,':',phecode.list$ICD
)

# Diagnosis dictionary from Athena
DX.list = read.delim("CONCEPT.csv", quote = '')
DX.relation = read.delim("CONCEPT_RELATIONSHIP.csv", 
                         quote = '')

# Select ICD codes and standardize the tag
DX.list = DX.list[
  grep("^ICD",DX.list$vocabulary_id),]
DX.list$vocabulary_id = gsub("CM",'',
                             DX.list$vocabulary_id)
DX.list$concept_full = paste0(
  DX.list$vocabulary_id, ':', 
  DX.list$concept_code
)
DX.relation = DX.relation[
  (DX.relation$concept_id_1 %in% DX.list$concept_id) &
    (DX.relation$concept_id_2 %in% DX.list$concept_id) &
  DX.relation$relationship_id == "Subsumes",
]

# Mapped concepts
map.id = DX.list$concept_id[
  DX.list$concept_full %in% 
    phecode.list$concept_full
]

# Optional: loop to find all sub-codes if necessary
subcode = TRUE
while(subcode)
{
  map.sub = unique(
    DX.relation$concept_id_2[
      DX.relation$concept_id_1 %in% map.id
    ]
  )
  subcode = !all(map.sub %in% map.id)
  map.id = unique(c(map.id,map.sub))
}

# Export the dictionary after removing deliminators
out.map = DX.list[DX.list$concept_id %in% map.id,]
out.map$concept_name = gsub(",",";",
                            out.map$concept_name)
out.map$concept_name = gsub('"',"|",
                            out.map$concept_name)
out.map$concept_name = gsub("'","-",
                            out.map$concept_name)
write.csv(out.map, file = "PheCode_714_1_Athena.csv",
          row.names = FALSE)


library(googleCloudStorageR)

gcs_auth()

my_bucket <- Sys.getenv("WORKSPACE_BUCKET")

# upload to bucket under data/ path
gcs_upload(
  file = "PheCode_714_1_Athena.csv",
  bucket = my_bucket,
  name = "data/PheCode_714_1_Athena.csv"   # bucket 里的保存路径
)
