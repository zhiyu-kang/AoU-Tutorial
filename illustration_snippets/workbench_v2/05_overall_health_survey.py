"""Code Snippet 5 (Workbench V2): survey table example.
"""

import pandas_gbq


v2_index = "wb-silky-artichoke-2408.C2024Q3R8_index_111825"

# Overall Health survey item selected in the V2 interface.
survey_item_id = 8015

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
    so.survey_item_id IN (
        SELECT descendant
        FROM `{v2_index}.T_HAD_surveyOverallHealth_default`
        WHERE ancestor = {survey_item_id}
        UNION ALL
        SELECT {survey_item_id}
    )
"""

try:
    v2_survey_df = pandas_gbq.read_gbq(
        v2_survey_sql,
        dialect="standard",
        use_bqstorage_api=True,
        progress_bar_type="tqdm_notebook",
    )
except Exception:
    v2_survey_df = pandas_gbq.read_gbq(
        v2_survey_sql,
        dialect="standard",
        use_bqstorage_api=False,
        progress_bar_type="tqdm_notebook",
    )

v2_survey_df.head(0)
