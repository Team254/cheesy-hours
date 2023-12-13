BUILD_DAYS_QUERY = """
WITH
    build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions)
SELECT
    build_days.build_date,
    NOT ISNULL(cheesy_frc_hours.optional_builds.date) AS optional
FROM
    build_days LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_date
ORDER BY build_date ASC;
"""

CALENDAR_BUILD_INFO_QUERY = """
WITH
    build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
    ordered_students AS (
        WITH counts AS (
            SELECT
                COUNT(*) as sessions_attended_count,
                student_id
            FROM cheesy_frc_hours.lab_sessions
            GROUP BY student_id
        )
        SELECT
            id as student_id,
            sessions_attended_count
        FROM
            cheesy_frc_hours.students
        LEFT JOIN counts ON cheesy_frc_hours.students.id=counts.student_id
    )
SELECT DISTINCT
    build_days.build_date,
    ordered_students.student_id,
    COALESCE(ordered_students.sessions_attended_count, 0) AS sessions_attended_count,
    NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
    ISNULL(cheesy_frc_hours.optional_builds.date) AS required,
    NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
FROM
    build_days CROSS JOIN ordered_students
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
    LEFT JOIN cheesy_frc_hours.lab_sessions ON DATE(cheesy_frc_hours.lab_sessions.time_in) = build_days.build_date
        AND cheesy_frc_hours.lab_sessions.student_id=ordered_students.student_id
        AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=ordered_students.student_id
        AND cheesy_frc_hours.excused_sessions.date=build_days.build_date
ORDER BY
    build_date ASC,
    sessions_attended_count DESC,
    student_id DESC;  -- fallback if students are tied in lab sessions
"""

CALENDAR_STUDENT_INFO_QUERY = """
WITH build_info AS (
    WITH
        build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total)
    SELECT DISTINCT
        build_days.build_date,
        students.id AS student_id,
        NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
        ISNULL(cheesy_frc_hours.optional_builds.date) AS required,
        NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        build_days CROSS JOIN cheesy_frc_hours.students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.lab_sessions ON DATE(cheesy_frc_hours.lab_sessions.time_in) = build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id=cheesy_frc_hours.students.id
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=cheesy_frc_hours.students.id
            AND cheesy_frc_hours.excused_sessions.date=build_days.build_date
        ORDER BY build_date ASC
), student_build_info AS (
    SELECT
        COUNT(IF(required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(attended AND required, 1, NULL)) AS required_attended_count,
        COUNT(IF(attended, 1, NULL)) AS total_attended_count,
        student_id
    FROM build_info
    GROUP BY student_id
)

SELECT * FROM student_build_info
ORDER BY total_attended_count DESC, student_id DESC;
"""