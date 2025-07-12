# Define the SQL query to retrieve all survey data for the specified questions (All participants)
survey_sql = """
    SELECT *
    FROM
        `""" + os.environ["WORKSPACE_CDR"] + """.ds_survey` answer   
    WHERE
        (
            question_concept_id IN (1234567)
        )"""

# Replace the * with the specific columns you need 
# (including answer.person_id, answer.survey_datetime, answer.survey, answer.question_concept_id,
# answer.question, answer.answer_concept_id, answer.answer, answer.survey_version_concept_id,
# answer.survey_version_name)

# Users need to change the question_concept_id value (1234567) 
# to the question_concept_id values they want to retrieve for their survey data.