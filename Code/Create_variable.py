import pandas as pd
import os

# Example DataFrame
df = pd.DataFrame({
    'person_id': [1, 2, 3],
    'date_of_birth': pd.to_datetime(['2000-01-01', '1995-05-15', '1988-12-30']),
    'condition_start_datetime_ehr': pd.to_datetime(['2020-01-01', '2019-06-15', '2021-12-30'])
})

# Compute last ehr follow-up time
df['age_at_last_ehr'] = df.apply(
    lambda row: ((row['condition_start_datetime_ehr'] - row['date_of_birth']).days // 365) if pd.notna(row['condition_start_datetime_ehr']) else None, 
    axis=1
)

# Users can change the column names and logic as needed