import os
import pandas as pd

# This query retrieves all EHR data for a specific condition_source_concept_id (1234567)

condition_sql = """
    SELECT
        c_occurrence.person_id,
        c_occurrence.condition_concept_id,
        c_standard_concept.concept_name as standard_concept_name,
        c_standard_concept.concept_code as standard_concept_code,
        c_standard_concept.vocabulary_id as standard_vocabulary,
        c_occurrence.condition_start_datetime,
        c_occurrence.condition_end_datetime,
        c_occurrence.condition_type_concept_id,
        c_type.concept_name as condition_type_concept_name,
        c_occurrence.stop_reason,
        c_occurrence.visit_occurrence_id,
        visit.concept_name as visit_occurrence_concept_name,
        c_occurrence.condition_source_value,
        c_occurrence.condition_source_concept_id,
        c_source_concept.concept_name as source_concept_name,
        c_source_concept.concept_code as source_concept_code,
        c_source_concept.vocabulary_id as source_vocabulary,
        c_occurrence.condition_status_source_value,
        c_occurrence.condition_status_concept_id,
        c_status.concept_name as condition_status_concept_name 
    FROM
        ( SELECT
            * 
        FROM
            `""" + os.environ["WORKSPACE_CDR"] + """.condition_occurrence` c_occurrence 
        WHERE
            (
                condition_source_concept_id IN (SELECT
                    DISTINCT c.concept_id 
                FROM
                    `""" + os.environ["WORKSPACE_CDR"] + """.cb_criteria` c 
                JOIN
                    (SELECT
                        CAST(cr.id as string) AS id       
                    FROM
                        `""" + os.environ["WORKSPACE_CDR"] + """.cb_criteria` cr       
                    WHERE
                        concept_id IN (1234567)       
                        AND full_text LIKE '%_rank1]%'      ) a 
                        ON (c.path LIKE CONCAT('%.', a.id, '.%') 
                        OR c.path LIKE CONCAT('%.', a.id) 
                        OR c.path LIKE CONCAT(a.id, '.%') 
                        OR c.path = a.id) 
                WHERE
                    is_standard = 0 
                    AND is_selectable = 1)
            )) c_occurrence 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.concept` c_standard_concept 
            ON c_occurrence.condition_concept_id = c_standard_concept.concept_id 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.concept` c_type 
            ON c_occurrence.condition_type_concept_id = c_type.concept_id 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.visit_occurrence` v 
            ON c_occurrence.visit_occurrence_id = v.visit_occurrence_id 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.concept` visit 
            ON v.visit_concept_id = visit.concept_id 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.concept` c_source_concept 
            ON c_occurrence.condition_source_concept_id = c_source_concept.concept_id 
    LEFT JOIN
        `""" + os.environ["WORKSPACE_CDR"] + """.concept` c_status 
            ON c_occurrence.condition_status_concept_id = c_status.concept_id"""


# User needs to change the condition_source_concept_id value (1234567)
# to the condition_source_concept_id values they want to retrieve for their EHR data.