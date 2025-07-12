# Extract EHR record for specific person_id
import pandas as pd
import os

# Define your df DataFrame (with person_id column) first
df = pd.DataFrame({
    'person_id': [1, 2, 3]
})

ehr_code_sql = """
    SELECT
        person_id,
        condition_concept_id,
        condition_start_datetime
        # Add other columns you need here
    FROM
        `""" + os.environ["WORKSPACE_CDR"] + f""".condition_occurrence` 
    WHERE person_id in {tuple(df['person_id'])}
    """