"""Code Snippet 3 (Workbench V2 / CDR v8): cohort demographics for the RA concept list."""

import os

import pandas
import pandas_gbq


concept_file = "Code/PheCode_714_1_Athena.csv"
concept_ids = (
    pandas.read_csv(concept_file)["concept_id"].dropna().astype(int).tolist()
)
ids_str = ", ".join(map(str, concept_ids))
cdr = os.environ["WORKSPACE_CDR"]

sql = f"""
SELECT
    p.person_id,
    g.concept_name AS gender,
    p.birth_datetime AS date_of_birth,
    r.concept_name AS race,
    e.concept_name AS ethnicity,
    s.concept_name AS sex_at_birth
FROM `{cdr}.person` p
LEFT JOIN `{cdr}.concept` g ON p.gender_concept_id = g.concept_id
LEFT JOIN `{cdr}.concept` r ON p.race_concept_id = r.concept_id
LEFT JOIN `{cdr}.concept` e ON p.ethnicity_concept_id = e.concept_id
LEFT JOIN `{cdr}.concept` s ON p.sex_at_birth_concept_id = s.concept_id
WHERE p.person_id IN (
    SELECT DISTINCT person_id
    FROM `{cdr}.condition_occurrence`
    WHERE condition_source_concept_id IN ({ids_str})
)
"""

person_df = pandas_gbq.read_gbq(sql, dialect="standard")
print(f"RA cohort size: {person_df['person_id'].nunique():,}")
