BUILD_DAYS_QUERY = """
SELECT
    build_days.build_date,
    NOT ISNULL(cheesy_frc_hours.optional_builds.date) AS optional
FROM
    (SELECT DISTINCT DATE(DATE_SUB(time_in, INTERVAL 8 HOUR)) AS build_date FROM cheesy_frc_hours.lab_sessions) AS build_days
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_date
ORDER BY build_date ASC;
"""

CALENDAR_BUILD_INFO_QUERY = """
SELECT DISTINCT
    *
FROM
    (SELECT 
        filtered_table.build_date,
            filtered_table.student_id,
            filtered_table.session_id,
            COALESCE(filtered_table.sessions_attended_count, 0) AS sessions_attended_count,
            NOT ISNULL(filtered_table.time_in) AS attended,
            ISNULL(cheesy_frc_hours.optional_builds.date) AS required,
            NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        (SELECT DISTINCT
        (CASE
                WHEN build_days.prev_day = 1 THEN DATE_SUB(build_days.build_date, INTERVAL 1 DAY)
                ELSE build_days.build_date
            END) AS build_date,
            ordered_students.student_id,
            filtered_sessions.time_in,
            ordered_students.sessions_attended_count,
            filtered_sessions.id AS session_id,
            filtered_sessions.excluded_from_total
    FROM
        (SELECT DISTINCT
        DATE(time_in) AS build_date, (HOUR(time_in) < 8) AS prev_day
    FROM
        cheesy_frc_hours.lab_sessions
    WHERE
        NOT excluded_from_total) AS build_days
    CROSS JOIN (SELECT 
        id AS student_id, counts.sessions_attended_count
    FROM
        cheesy_frc_hours.students
    LEFT JOIN (SELECT 
        COUNT(*) AS sessions_attended_count, student_id
    FROM
        (SELECT DISTINCT
        time_in, student_id
    FROM
        cheesy_frc_hours.lab_sessions
    GROUP BY DATE(DATE_SUB(time_in, INTERVAL 8 HOUR)) , student_id) AS condensed_sessions
    GROUP BY student_id) AS counts ON cheesy_frc_hours.students.id = counts.student_id) AS ordered_students
    LEFT JOIN (SELECT 
        time_in, student_id, id, excluded_from_total
    FROM
        cheesy_frc_hours.lab_sessions) AS filtered_sessions ON filtered_sessions.student_id = ordered_students.student_id
        AND DATE(filtered_sessions.time_in) = build_days.build_date
        AND (HOUR(filtered_sessions.time_in) < 8) = build_days.prev_day
        AND NOT filtered_sessions.excluded_from_total) AS filtered_table
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date = filtered_table.build_date
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id = filtered_table.student_id
        AND cheesy_frc_hours.excused_sessions.date = filtered_table.build_date) AS ungrouped_table
GROUP BY build_date , student_id
ORDER BY build_date ASC , sessions_attended_count DESC , student_id DESC;  -- fallback if students are tied in lab sessions
"""

CALENDAR_STUDENT_INFO_QUERY = """
SELECT 
    *
FROM
    (SELECT 
        COUNT(IF(required
                AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
            COUNT(IF(attended AND required, 1, NULL)) AS required_attended_count,
            COUNT(IF(attended, 1, NULL)) AS total_attended_count,
            student_id
    FROM
        (SELECT DISTINCT
        filtered_table.build_date,
            filtered_table.student_id,
            NOT ISNULL(filtered_table.time_in) AS attended,
            ISNULL(cheesy_frc_hours.optional_builds.date) AS required,
            NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        (SELECT DISTINCT
        (CASE
                WHEN build_days.prev_day = 1 THEN DATE_SUB(build_days.build_date, INTERVAL 1 DAY)
                ELSE build_days.build_date
            END) AS build_date,
            cheesy_frc_hours.students.id AS student_id,
            filtered_sessions.time_in,
            filtered_sessions.id AS session_id,
            filtered_sessions.excluded_from_total
    FROM
        (SELECT DISTINCT
        DATE(time_in) AS build_date, (HOUR(time_in) < 8) AS prev_day
    FROM
        cheesy_frc_hours.lab_sessions
    WHERE
        NOT excluded_from_total) AS build_days
    CROSS JOIN cheesy_frc_hours.students
    LEFT JOIN (SELECT 
        time_in, student_id, id, excluded_from_total
    FROM
        cheesy_frc_hours.lab_sessions) AS filtered_sessions ON filtered_sessions.student_id = cheesy_frc_hours.students.id
        AND DATE(filtered_sessions.time_in) = build_days.build_date
        AND NOT filtered_sessions.excluded_from_total) AS filtered_table
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date = filtered_table.build_date
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id = filtered_table.student_id
        AND cheesy_frc_hours.excused_sessions.date = filtered_table.build_date
    ORDER BY build_date ASC) AS build_info
    GROUP BY student_id) AS student_build_info
ORDER BY total_attended_count DESC , student_id DESC;
"""