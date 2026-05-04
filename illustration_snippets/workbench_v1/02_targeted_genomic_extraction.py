"""Code Snippet 2 (Workbench V1): targeted SNP extraction from the ACAF-threshold MT."""

import os

import hail as hl
import pandas as pd


# Load the ACAF-threshold WGS MatrixTable.
hl.default_reference("GRCh38")
mt = hl.read_matrix_table(os.getenv("WGS_ACAF_THRESHOLD_SPLIT_HAIL_PATH"))

# Filter by person id.
person_df = pd.read_csv("Person_IDs.csv")
keep_ids = person_df["person_id"].astype(str).tolist()
mt = mt.filter_cols(hl.literal(keep_ids).contains(mt.s))

# Define target SNP loci.
snp_df = pd.read_csv("RA_target_SNPs.csv")
intervals = [
    hl.parse_locus_interval(iv, reference_genome="GRCh38")
    for iv in snp_df["interval"]
]
mt_subset = hl.filter_intervals(mt, intervals)

# Create a SNP ID column.
mt_subset = mt_subset.annotate_rows(
    snp_id=mt_subset.locus.contig.replace("chr", "")
    + ":"
    + hl.str(mt_subset.locus.position)
    + ":"
    + mt_subset.alleles[0]
    + ":"
    + mt_subset.alleles[1]
)

# Annotate entries with alternate-allele count (0/1/2).
mt_snps = mt_subset.annotate_entries(
    allele_count=hl.case()
    .when(mt_subset.GT.is_hom_ref(), 0)
    .when(mt_subset.GT.is_het(), 1)
    .when(mt_subset.GT.is_hom_var(), 2)
    .or_missing()
)

# Reshape to participant x SNP matrix.
snp_matrix = (
    mt_snps.entries()
    .key_by()
    .select("s", "snp_id", "allele_count")
    .to_pandas()
    .pivot(index="s", columns="snp_id", values="allele_count")
)
