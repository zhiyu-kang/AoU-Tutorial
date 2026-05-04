"""Code Snippet 1 (Workbench V1): extract EHR condition records for the RA cohort."""

import os

import pandas as pd


# Load the RA cohort person_ids.
keep_ids = pd.read_csv("Person_IDs.csv")["person_id"].tolist()
ids_str = ", ".join(map(str, keep_ids))
cdr = os.environ["WORKSPACE_CDR"]

# Extract EHR condition records for the cohort.
sql = f"""
SELECT person_id,
       condition_concept_id,
       condition_start_datetime
FROM `{cdr}.condition_occurrence`
WHERE person_id IN ({ids_str})
"""

ra_case_ehr_code = pd.read_gbq(
    sql,
    dialect="standard",
    use_bqstorage_api=("BIGQUERY_STORAGE_API_ENABLED" in os.environ),
    progress_bar_type="tqdm_notebook",
)
