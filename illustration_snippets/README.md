# Illustration Code Snippets

This directory contains the illustration snippets transcribed from the revision PDF and
organized into upload-ready files for the GitHub repository.

## Workbench Version 1

- [`workbench_v1/01_ehr_condition_records.py`](workbench_v1/01_ehr_condition_records.py)
  - Representative BigQuery extraction of RA cohort EHR condition records from
    `condition_occurrence`.
- [`workbench_v1/02_targeted_genomic_extraction.py`](workbench_v1/02_targeted_genomic_extraction.py)
  - Hail-based targeted extraction of selected RA SNPs from the ACAF-threshold
    MatrixTable.
- [`workbench_v1/03_cohort_demographics.py`](workbench_v1/03_cohort_demographics.py)
  - Cohort demographics query driven by the expanded RA concept list.
- [`workbench_v1/04_condition_records.py`](workbench_v1/04_condition_records.py)
  - Longitudinal condition-record extraction for identified RA participants.
- [`workbench_v1/05_overall_health_survey.py`](workbench_v1/05_overall_health_survey.py)
  - Extraction of one Overall Health survey question from `ds_survey`.

## Researcher Workbench Version 2

These files correspond to the new Version 2 examples added during revision. They keep
the Version 1 examples intact while showing the main V2 adaptations.

- [`workbench_v2/03_cohort_demographics.py`](workbench_v2/03_cohort_demographics.py)
  - Cohort demographics query for the V2 / CDR v8 environment. The concept-list-based
    OMOP query pattern remains essentially unchanged.
- [`workbench_v2/04_condition_records.py`](workbench_v2/04_condition_records.py)
  - V2 indexed-table version of the condition-record extraction using
    `T_ENT_conditionOccurrence` and `T_DISP_*` display fields.
- [`workbench_v2/05_overall_health_survey.py`](workbench_v2/05_overall_health_survey.py)
  - V2 indexed-table survey example using `T_ENT_surveyOccurrence`. This is an
    illustrative adaptation because the PDF text describes the V2 approach but does not
    show the full code block.

## Notes

- The files above are illustration snippets, not full production pipelines.
- Several snippets assume the standard All of Us environment variables such as
  `WORKSPACE_CDR`, `WORKSPACE_BUCKET`, and `BIGQUERY_STORAGE_API_ENABLED`.
- The revision screenshots explicitly showed the V2 indexed dataset namespace
  `wb-silky-artichoke-2408.C2024Q3R8_index_111825`; update that value if your current
  workspace uses a different index dataset.
