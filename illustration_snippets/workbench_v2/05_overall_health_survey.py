"""Code Snippet 5 (Workbench V2 / CDR v8): indexed survey table example.

The PDF text describes the V2 extraction pattern but does not show the full code block.
This snippet is a cleaned illustrative adaptation following the manuscript text and the
indexed-table naming pattern used in the V2 condition-record example above.
"""

import pandas_gbq


# Overall Health survey question:
# "How often do you have problems learning about your medical condition
# because of difficulty understanding written information?"
question_concept_id = 1585778

# Replace with the current indexed dataset in your Workbench 2.0 workspace if needed.
v2_index = "wb-silky-artichoke-2408.C2024Q3R8_index_111825"

v2_survey_sql = f"""
SELECT
    so.person_id,
    so.survey_datetime,
    so.T_DISP_survey AS survey,
    so.T_DISP_question AS question,
    so.T_DISP_answer AS answer
FROM
    `{v2_index}.T_ENT_surveyOccurrence` so
WHERE
    so.question_concept_id = {question_concept_id}
"""

v2_survey_df = pandas_gbq.read_gbq(
    v2_survey_sql,
    dialect="standard",
    use_bqstorage_api=True,
    progress_bar_type="tqdm_notebook",
)

v2_survey_df.head(0)
