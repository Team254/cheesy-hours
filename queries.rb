BUILD_DAYS_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions),
    optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
    scheduled_build_days AS (SELECT date AS build_date, optional FROM cheesy_frc_hours.scheduled_build_days),
    all_build_days AS (
        SELECT build_date FROM lab_build_days
        UNION
        SELECT build_date FROM optional_build_days
        UNION
        SELECT build_date FROM scheduled_build_days
    )
SELECT
    all_build_days.build_date,
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 1
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 1
        ELSE 0
    END AS optional
FROM
    all_build_days 
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=all_build_days.build_date
    LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=all_build_days.build_date
ORDER BY build_date ASC;
"""

BUILD_DAYS_RANGE_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions),
    optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
    scheduled_build_days AS (SELECT date AS build_date, optional FROM cheesy_frc_hours.scheduled_build_days),
    all_build_days AS (
        SELECT build_date FROM lab_build_days
        UNION
        SELECT build_date FROM optional_build_days
        UNION
        SELECT build_date FROM scheduled_build_days
    )
SELECT
    all_build_days.build_date,
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 1
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 1
        ELSE 0
    END AS optional
FROM
    all_build_days
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=all_build_days.build_date
    LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=all_build_days.build_date
WHERE
    all_build_days.build_date BETWEEN ? AND ?
    AND (
        ? = 0
        OR (cheesy_frc_hours.optional_builds.date IS NULL
            AND (cheesy_frc_hours.scheduled_build_days.optional IS NULL
                OR cheesy_frc_hours.scheduled_build_days.optional = 0))
    )
ORDER BY build_date ASC;
"""

CALENDAR_BUILD_INFO_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
    optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
    scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
    build_days AS (
        SELECT build_date FROM lab_build_days
        UNION
        SELECT build_date FROM optional_build_days
        UNION
        SELECT build_date FROM scheduled_build_days
    ),
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
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 0
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 0
        ELSE 1
    END AS required,
    NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused,
    cheesy_frc_hours.lab_sessions.id AS session_id
    FROM
        build_days CROSS JOIN ordered_students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
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

CALENDAR_BUILD_INFO_RANGE_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
    optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
    scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
    build_days AS (
        SELECT build_date FROM lab_build_days
        UNION
        SELECT build_date FROM optional_build_days
        UNION
        SELECT build_date FROM scheduled_build_days
    ),
    filtered_build_days AS (
        SELECT build_days.build_date
        FROM build_days
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
        WHERE build_days.build_date BETWEEN ? AND ?
            AND (
                ? = 0
                OR (cheesy_frc_hours.optional_builds.date IS NULL
                    AND (cheesy_frc_hours.scheduled_build_days.optional IS NULL
                        OR cheesy_frc_hours.scheduled_build_days.optional = 0))
            )
    ),
    ordered_students AS (
        WITH counts AS (
            SELECT
                COUNT(*) as sessions_attended_count,
                cheesy_frc_hours.lab_sessions.student_id
            FROM cheesy_frc_hours.lab_sessions
            JOIN filtered_build_days ON DATE(cheesy_frc_hours.lab_sessions.time_in) = filtered_build_days.build_date
            WHERE NOT cheesy_frc_hours.lab_sessions.excluded_from_total
            GROUP BY cheesy_frc_hours.lab_sessions.student_id
        )
        SELECT
            id as student_id,
            sessions_attended_count
        FROM
            cheesy_frc_hours.students
        LEFT JOIN counts ON cheesy_frc_hours.students.id=counts.student_id
    )
SELECT DISTINCT
    filtered_build_days.build_date,
    ordered_students.student_id,
    COALESCE(ordered_students.sessions_attended_count, 0) AS sessions_attended_count,
    NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 0
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 0
        ELSE 1
    END AS required,
    NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused,
    cheesy_frc_hours.lab_sessions.id AS session_id
    FROM
        filtered_build_days CROSS JOIN ordered_students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
    LEFT JOIN cheesy_frc_hours.lab_sessions ON DATE(cheesy_frc_hours.lab_sessions.time_in) = filtered_build_days.build_date
        AND cheesy_frc_hours.lab_sessions.student_id=ordered_students.student_id
        AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=ordered_students.student_id
        AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
ORDER BY
    build_date ASC,
    sessions_attended_count DESC,
    student_id DESC;  -- fallback if students are tied in lab sessions
"""

CALENDAR_STUDENT_INFO_QUERY = """
WITH build_info AS (
    WITH
        lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
        optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
        scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
        build_days AS (
            SELECT build_date FROM lab_build_days
            UNION
            SELECT build_date FROM optional_build_days
            UNION
            SELECT build_date FROM scheduled_build_days
        )
    SELECT DISTINCT
        build_days.build_date,
        students.id AS student_id,
        NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
        CASE
            WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 0
            WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 0
            ELSE 1
        END AS required,
        NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        build_days CROSS JOIN cheesy_frc_hours.students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
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

CALENDAR_STUDENT_INFO_RANGE_QUERY = """
WITH build_info AS (
    WITH
        lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
        optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
        scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
        build_days AS (
            SELECT build_date FROM lab_build_days
            UNION
            SELECT build_date FROM optional_build_days
            UNION
            SELECT build_date FROM scheduled_build_days
        ),
        filtered_build_days AS (
            SELECT build_days.build_date
            FROM build_days
            LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
            LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
            WHERE build_days.build_date BETWEEN ? AND ?
                AND (
                    ? = 0
                    OR (cheesy_frc_hours.optional_builds.date IS NULL
                        AND (cheesy_frc_hours.scheduled_build_days.optional IS NULL
                            OR cheesy_frc_hours.scheduled_build_days.optional = 0))
                )
        )
    SELECT DISTINCT
        filtered_build_days.build_date,
        students.id AS student_id,
        NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
        CASE
            WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 0
            WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 0
            ELSE 1
        END AS required,
        NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        filtered_build_days CROSS JOIN cheesy_frc_hours.students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.lab_sessions ON DATE(cheesy_frc_hours.lab_sessions.time_in) = filtered_build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id=cheesy_frc_hours.students.id
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=cheesy_frc_hours.students.id
            AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
        ORDER BY build_date ASC
), student_build_info AS (
    SELECT
        COUNT(IF(required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(attended AND required, 1, NULL)) AS required_attended_count,
        COUNT(IF(attended, 1, NULL)) AS total_attended_count,
        COUNT(IF(required AND NOT attended AND NOT excused, 1, NULL)) AS unexcused_count,
        student_id
    FROM build_info
    GROUP BY student_id
)

SELECT * FROM student_build_info
ORDER BY total_attended_count DESC, student_id DESC;
"""

STUDENT_ATTENDANCE_RANGE_QUERY = """
WITH build_info AS (
    WITH
        lab_build_days AS (SELECT DISTINCT DATE(time_in) AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
        optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
        scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
        build_days AS (
            SELECT build_date FROM lab_build_days
            UNION
            SELECT build_date FROM optional_build_days
            UNION
            SELECT build_date FROM scheduled_build_days
        ),
        filtered_build_days AS (
            SELECT build_date FROM build_days WHERE build_date BETWEEN ? AND ?
        )
    SELECT DISTINCT
        filtered_build_days.build_date,
        NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in) as attended,
        CASE
            WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 0
            WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) AND cheesy_frc_hours.scheduled_build_days.optional = 1 THEN 0
            ELSE 1
        END AS required,
        NOT ISNULL(cheesy_frc_hours.excused_sessions.date) AS excused
    FROM
        filtered_build_days
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.lab_sessions ON DATE(cheesy_frc_hours.lab_sessions.time_in) = filtered_build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id = ?
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id = ?
            AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
    ORDER BY build_date ASC
), attendance_summary AS (
    SELECT
        COUNT(IF(required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(attended AND required, 1, NULL)) AS required_attended_count,
        COUNT(IF(attended, 1, NULL)) AS total_attended_count,
        COUNT(IF(required AND NOT attended AND NOT excused, 1, NULL)) AS unexcused_count
    FROM build_info
)

SELECT * FROM attendance_summary;
"""
