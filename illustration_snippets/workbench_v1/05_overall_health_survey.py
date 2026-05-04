"""Code Snippet 5 (Workbench V1): one Overall Health survey question."""

import os

import pandas as pd
import pandas_gbq


cdr = os.environ["WORKSPACE_CDR"]

# Overall Health survey question:
# "How often do you have problems learning about your medical condition
# because of difficulty understanding written information?"
question_concept_id = 1585778

v1_survey_sql = f"""
SELECT
    person_id,
    survey_datetime,
    survey,
    question,
    answer
FROM
    `{cdr}.ds_survey`
WHERE
    question_concept_id = {question_concept_id}
"""

v1_survey_df = pandas_gbq.read_gbq(
    v1_survey_sql,
    dialect="standard",
    use_bqstorage_api=("BIGQUERY_STORAGE_API_ENABLED" in os.environ),
    progress_bar_type="tqdm_notebook",
)

v1_survey_df.head(0)
