"""Code Snippet 4 (Workbench V2 / CDR v8): indexed condition records example."""

import os

import pandas
import pandas_gbq


# Read user-provided RA PheCode concept list.
concept_file = "Code/PheCode_714_1_Athena.csv"
concept_ids = (
    pandas.read_csv(concept_file)["concept_id"].dropna().astype(int).tolist()
)
ids_str = ", ".join(map(str, concept_ids))

# V2 indexed dataset shown in the revision screenshot.
v2_index = "wb-silky-artichoke-2408.C2024Q3R8_index_111825"

sql = f"""
SELECT
    co.person_id,
    co.condition_concept_id,
    co.T_DISP_standard_concept_name AS standard_concept_name,
    co.condition_start_datetime,
    co.condition_end_datetime,
    co.condition_source_concept_id,
    co.T_DISP_source_concept_code AS source_concept_code
FROM
    `{v2_index}.T_ENT_conditionOccurrence` co
WHERE
    co.condition_source_concept_id IN ({ids_str})
"""

condition_df = pandas_gbq.read_gbq(
    sql,
    dialect="standard",
    use_bqstorage_api=True,
    progress_bar_type="tqdm_notebook",
)

condition_df.head(0)
