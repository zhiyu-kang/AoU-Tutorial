"""Code Snippet 4 (Workbench V1): longitudinal condition records for the RA cohort."""

import os

import pandas


concept_ids = pandas.read_csv("PheCode_714_1_Athena.csv")["concept_id"].tolist()
ids_str = ", ".join(map(str, concept_ids))
cdr = os.environ["WORKSPACE_CDR"]

sql = f"""
SELECT co.person_id,
       co.condition_concept_id,
       std.concept_name AS standard_concept_name,
       co.condition_start_datetime,
       co.condition_end_datetime,
       co.condition_source_concept_id,
       src.concept_code AS source_concept_code
FROM `{cdr}.condition_occurrence` co
LEFT JOIN `{cdr}.concept` std ON co.condition_concept_id = std.concept_id
LEFT JOIN `{cdr}.concept` src ON co.condition_source_concept_id = src.concept_id
WHERE co.condition_source_concept_id IN ({ids_str})
"""

condition_df = pandas.read_gbq(sql, dialect="standard")
condition_df.head(0)
