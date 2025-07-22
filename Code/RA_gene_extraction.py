# save the envirnoment variables
import os
bucket = os.getenv("WORKSPACE_BUCKET")

# Import Hail and Initialize Spark
import hail as hl
hl.default_reference(new_default_reference = "GRCh38")

# using env variable to load the WGS common variant Hail MatrixTable (See https://support.researchallofus.org/hc/en-us/articles/29475233432212-Controlled-CDR-Directory for more environment variables)
mt_wgs_path = os.getenv("WGS_ACAF_THRESHOLD_MULTI_HAIL_PATH")

# read the Hail MatrixTable using the function read_matrix_table
mt = hl.read_matrix_table(mt_wgs_path)
mt.count()

# # filter by person_id (if you wish)
# keep_ids = ['1166759']
# mt = mt.filter_cols(hl.literal(keep_ids).contains(mt.s))

# filter SNPs by interval
test_intervals = [
    'chr14:104920174-104920175',
    'chr6:159082054-159082055',
    'chr14:68287978-68287979',
    'chr6:36414159-36414160',
    'chr1:116738074-116738075',  
    'chr5:143224856-143224857',      
    'chr9:34710263-34710264',        
    'chr13:39781776-39781777',       
    'chr12:111446804-111446805',
    'chr12:45976333-45976334',
]

interval_exprs = [hl.parse_locus_interval(iv, reference_genome='GRCh38')
                  for iv in test_intervals]
mt_small = hl.filter_intervals(mt, interval_exprs)

# create a new column with SNP ID
mt_small = mt_small.annotate_rows(snp_id=mt_small.locus.contig.replace("chr", "") + ":" + hl.str(mt_small.locus.position) + ":" + mt_small.alleles[0] + ":" + mt_small.alleles[1])
snp_ids = [
    "14:104920174:G:A", "6:159082054:A:G", "14:68287978:G:A",
    "6:36414159:G:GA", "13:39781776:T:C", "12:45976333:C:G",
    "12:111446804:T:C", "9:34710263:G:A", "5:143224856:A:G",
    "1:116738074:C:T"
]

# Filter the rows to keep only SNPs of interest
snp_set = hl.set(snp_ids)
mt_filtered = mt_small.filter_rows(snp_set.contains(mt_small.snp_id))
mt_filtered = mt_filtered.checkpoint("mt_filtered.mt", overwrite=True)

# Annotate entries with the genotype allele count (number of alternate alleles per individual)
mt_snps = mt_filtered.annotate_entries(allele_count=hl.case()
                         .when(mt_filtered.GT.is_hom_ref(), 0)  # Homozygous reference → 0 alt alleles
                         .when(mt_filtered.GT.is_het(), 1)      # Heterozygous → 1 alt allele
                         .when(mt_filtered.GT.is_hom_var(), 2)  # Homozygous alternate → 2 alt alleles
                         .or_missing())  # Missing data remains missing

# Extract only the necessary columns
table = mt_snps.entries()
table = table.key_by()
table = table.select('s', 'snp_id', 'allele_count')

# Convert to a wide format: row = individuals, columns = SNPs
snp_matrix = table.to_pandas().pivot(index="s", columns="snp_id", values="allele_count")
snp_matrix = snp_matrix.reset_index().rename(columns={"s": "person_id"})
snp_matrix['person_id'] = snp_matrix['person_id'].astype(int)

# Save the DataFrame to a CSV file
snp_matrix.to_csv("extract_gene_test.csv", index=False)



# -------------------------------------------
# Save the DataFrame to Google Cloud Storage
# -------------------------------------------

# read the DataFrame from the CSV file
# This assumes you have already run the previous code to create 'extract_gene_test.csv'
import pandas as pd
df = pd.read_csv('extract_gene_test.csv')

# set up the environment for saving to Google Cloud Storage
import os
import subprocess
import numpy as np
import pandas as pd

# This code saves your dataframe into a csv file in a "data" folder in Google Bucket

# Replace df with THE NAME OF YOUR DATAFRAME
my_dataframe = df

# Define the destination filename
destination_filename = 'RA_wgs.csv'

# save dataframe in a csv file in the same workspace as the notebook
my_dataframe.to_csv(destination_filename, index=False)

# get the bucket name
my_bucket = os.getenv('WORKSPACE_BUCKET')

# copy csv file to the bucket
args = ["gsutil", "cp", f"./{destination_filename}", f"{my_bucket}/data/"]
output = subprocess.run(args, capture_output=True)

# print output from gsutil
output.stderr

