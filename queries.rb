REQUIRED_BUILD_DAYS_SQL = REQUIRED_BUILD_DAYS.map { |day| "'#{day}'" }.join(", ")

TIMED_BUILD_ATTENDANCE_CTE = """
timed_session_intervals AS (
    SELECT
        cheesy_frc_hours.scheduled_build_days.date AS build_date,
        cheesy_frc_hours.lab_sessions.student_id,
        GREATEST(cheesy_frc_hours.lab_sessions.time_in, cheesy_frc_hours.scheduled_build_days.starts_at) AS interval_start,
        LEAST(cheesy_frc_hours.lab_sessions.time_out, cheesy_frc_hours.scheduled_build_days.ends_at) AS interval_end
    FROM cheesy_frc_hours.scheduled_build_days
    JOIN cheesy_frc_hours.lab_sessions
        ON cheesy_frc_hours.lab_sessions.time_in < cheesy_frc_hours.scheduled_build_days.ends_at
        AND cheesy_frc_hours.lab_sessions.time_out > cheesy_frc_hours.scheduled_build_days.starts_at
        AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
    WHERE
        NOT ISNULL(cheesy_frc_hours.scheduled_build_days.starts_at)
        AND NOT ISNULL(cheesy_frc_hours.scheduled_build_days.ends_at)
        AND NOT ISNULL(cheesy_frc_hours.lab_sessions.time_out)
),
timed_intervals_with_previous_end AS (
    SELECT
        timed_session_intervals.*,
        MAX(interval_end) OVER (
            PARTITION BY build_date, student_id
            ORDER BY interval_start, interval_end
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS previous_end
    FROM timed_session_intervals
),
timed_interval_groups AS (
    SELECT
        timed_intervals_with_previous_end.*,
        SUM(CASE WHEN previous_end IS NULL OR interval_start > previous_end THEN 1 ELSE 0 END) OVER (
            PARTITION BY build_date, student_id
            ORDER BY interval_start, interval_end
        ) AS interval_group
    FROM timed_intervals_with_previous_end
),
timed_merged_intervals AS (
    SELECT
        build_date,
        student_id,
        interval_group,
        MIN(interval_start) AS interval_start,
        MAX(interval_end) AS interval_end
    FROM timed_interval_groups
    GROUP BY
        build_date,
        student_id,
        interval_group
),
timed_build_attendance AS (
    SELECT
        build_date,
        student_id,
        SUM(TIMESTAMPDIFF(SECOND, interval_start, interval_end)) AS attended_seconds
    FROM timed_merged_intervals
    GROUP BY
        build_date,
        student_id
)
"""

def utc_to_local_date(utc_column)
  # PDT (UTC-7): second Sunday of March 10:00 UTC to first Sunday of November 09:00 UTC
  # PST (UTC-8): rest of year
  pdt_start = "CONCAT(YEAR(#{utc_column}), '-03-', LPAD(8 + (8 - DAYOFWEEK(CONCAT(YEAR(#{utc_column}), '-03-01'))) % 7, 2, '0'), ' 10:00:00')"
  pdt_end = "CONCAT(YEAR(#{utc_column}), '-11-', LPAD(1 + (8 - DAYOFWEEK(CONCAT(YEAR(#{utc_column}), '-11-01'))) % 7, 2, '0'), ' 09:00:00')"
  "DATE(#{utc_column} - INTERVAL CASE WHEN #{utc_column} >= #{pdt_start} AND #{utc_column} < #{pdt_end} THEN 7 ELSE 8 END HOUR)"
end

def optional_build_case(build_date_ref)
  <<~SQL
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.date) THEN cheesy_frc_hours.scheduled_build_days.optional
        WHEN NOT ISNULL(cheesy_frc_hours.optional_builds.date) THEN 1
        WHEN DAYNAME(#{build_date_ref}) IN (#{REQUIRED_BUILD_DAYS_SQL}) THEN 0
        ELSE 1
    END
  SQL
end

def build_attended_case
  <<~SQL
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.starts_at)
            AND NOT ISNULL(cheesy_frc_hours.scheduled_build_days.ends_at)
        THEN
            cheesy_frc_hours.scheduled_build_days.ends_at <= UTC_TIMESTAMP()
            AND COALESCE(timed_build_attendance.attended_seconds, 0) * 3 >=
                TIMESTAMPDIFF(SECOND, cheesy_frc_hours.scheduled_build_days.starts_at, cheesy_frc_hours.scheduled_build_days.ends_at) * 2
        ELSE MAX(NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in))
    END
  SQL
end

def build_finalized_case
  <<~SQL
    CASE
        WHEN NOT ISNULL(cheesy_frc_hours.scheduled_build_days.starts_at)
            AND NOT ISNULL(cheesy_frc_hours.scheduled_build_days.ends_at)
        THEN cheesy_frc_hours.scheduled_build_days.ends_at <= UTC_TIMESTAMP()
        ELSE 1
    END
  SQL
end

BUILD_DAYS_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
    #{optional_build_case("all_build_days.build_date")} AS optional,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at
FROM
    all_build_days 
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=all_build_days.build_date
    LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=all_build_days.build_date
ORDER BY build_date ASC;
"""

BUILD_DAYS_RANGE_QUERY = """
WITH
    lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
    #{optional_build_case("all_build_days.build_date")} AS optional,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at
FROM
    all_build_days
    LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=all_build_days.build_date
    LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=all_build_days.build_date
WHERE
    all_build_days.build_date BETWEEN ? AND ?
    AND (
        ? = 0
        OR (#{optional_build_case("all_build_days.build_date")}) = 0
    )
ORDER BY build_date ASC;
"""

CALENDAR_BUILD_INFO_QUERY = """
WITH
    #{TIMED_BUILD_ATTENDANCE_CTE},
    lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
                COUNT(DISTINCT #{utc_to_local_date("time_in")}) as sessions_attended_count,
                student_id
            FROM cheesy_frc_hours.lab_sessions
            WHERE NOT excluded_from_total
            GROUP BY student_id
        )
        SELECT
            id as student_id,
            sessions_attended_count
        FROM
            cheesy_frc_hours.students
        LEFT JOIN counts ON cheesy_frc_hours.students.id=counts.student_id
    )
SELECT
    build_days.build_date,
    ordered_students.student_id,
    COALESCE(ordered_students.sessions_attended_count, 0) AS sessions_attended_count,
    #{build_attended_case} AS attended,
    #{build_finalized_case} AS finalized,
    CASE
        WHEN (#{optional_build_case("build_days.build_date")}) = 1 THEN 0
        ELSE 1
    END AS required,
    MAX(NOT ISNULL(cheesy_frc_hours.excused_sessions.date)) AS excused,
    MAX(cheesy_frc_hours.lab_sessions.id) AS session_id,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at
    FROM
        build_days CROSS JOIN ordered_students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
        LEFT JOIN timed_build_attendance ON timed_build_attendance.build_date=build_days.build_date
            AND timed_build_attendance.student_id=ordered_students.student_id
    LEFT JOIN cheesy_frc_hours.lab_sessions ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = build_days.build_date
        AND cheesy_frc_hours.lab_sessions.student_id=ordered_students.student_id
        AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=ordered_students.student_id
        AND cheesy_frc_hours.excused_sessions.date=build_days.build_date
GROUP BY
    build_days.build_date,
    ordered_students.student_id,
    ordered_students.sessions_attended_count,
    cheesy_frc_hours.optional_builds.date,
    cheesy_frc_hours.scheduled_build_days.date,
    cheesy_frc_hours.scheduled_build_days.optional,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at,
    timed_build_attendance.attended_seconds
ORDER BY
    build_date ASC,
    sessions_attended_count DESC,
    student_id DESC;
"""

CALENDAR_BUILD_INFO_RANGE_QUERY = """
WITH
    #{TIMED_BUILD_ATTENDANCE_CTE},
    lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
                OR (#{optional_build_case("build_days.build_date")}) = 0
            )
    ),
    ordered_students AS (
        WITH counts AS (
            SELECT
                COUNT(DISTINCT filtered_build_days.build_date) as sessions_attended_count,
                cheesy_frc_hours.lab_sessions.student_id
            FROM cheesy_frc_hours.lab_sessions
            JOIN filtered_build_days ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = filtered_build_days.build_date
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
SELECT
    filtered_build_days.build_date,
    ordered_students.student_id,
    COALESCE(ordered_students.sessions_attended_count, 0) AS sessions_attended_count,
    #{build_attended_case} AS attended,
    #{build_finalized_case} AS finalized,
    CASE
        WHEN (#{optional_build_case("filtered_build_days.build_date")}) = 1 THEN 0
        ELSE 1
    END AS required,
    MAX(NOT ISNULL(cheesy_frc_hours.excused_sessions.date)) AS excused,
    MAX(cheesy_frc_hours.lab_sessions.id) AS session_id,
    MAX(CASE
        WHEN NOT ISNULL(cheesy_frc_hours.lab_sessions.time_in)
            AND ISNULL(cheesy_frc_hours.lab_sessions.time_out)
        THEN 1
        ELSE 0
    END) AS signed_in,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at
    FROM
        filtered_build_days CROSS JOIN ordered_students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
        LEFT JOIN timed_build_attendance ON timed_build_attendance.build_date=filtered_build_days.build_date
            AND timed_build_attendance.student_id=ordered_students.student_id
    LEFT JOIN cheesy_frc_hours.lab_sessions ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = filtered_build_days.build_date
        AND cheesy_frc_hours.lab_sessions.student_id=ordered_students.student_id
        AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
    LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=ordered_students.student_id
        AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
GROUP BY
    filtered_build_days.build_date,
    ordered_students.student_id,
    ordered_students.sessions_attended_count,
    cheesy_frc_hours.optional_builds.date,
    cheesy_frc_hours.scheduled_build_days.date,
    cheesy_frc_hours.scheduled_build_days.optional,
    cheesy_frc_hours.scheduled_build_days.starts_at,
    cheesy_frc_hours.scheduled_build_days.ends_at,
    timed_build_attendance.attended_seconds
ORDER BY
    build_date ASC,
    sessions_attended_count DESC,
    student_id DESC;
"""

CALENDAR_STUDENT_INFO_QUERY = """
WITH build_info AS (
    WITH
        #{TIMED_BUILD_ATTENDANCE_CTE},
        lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
        optional_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.optional_builds),
        scheduled_build_days AS (SELECT date AS build_date FROM cheesy_frc_hours.scheduled_build_days),
        build_days AS (
            SELECT build_date FROM lab_build_days
            UNION
            SELECT build_date FROM optional_build_days
            UNION
            SELECT build_date FROM scheduled_build_days
        )
    SELECT
        build_days.build_date,
        students.id AS student_id,
        #{build_attended_case} AS attended,
        #{build_finalized_case} AS finalized,
        CASE
            WHEN (#{optional_build_case("build_days.build_date")}) = 1 THEN 0
            ELSE 1
        END AS required,
        MAX(NOT ISNULL(cheesy_frc_hours.excused_sessions.date)) AS excused
    FROM
        build_days CROSS JOIN cheesy_frc_hours.students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=build_days.build_date
        LEFT JOIN timed_build_attendance ON timed_build_attendance.build_date=build_days.build_date
            AND timed_build_attendance.student_id=students.id
        LEFT JOIN cheesy_frc_hours.lab_sessions ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id=cheesy_frc_hours.students.id
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=cheesy_frc_hours.students.id
            AND cheesy_frc_hours.excused_sessions.date=build_days.build_date
        GROUP BY
            build_days.build_date,
            students.id,
            cheesy_frc_hours.optional_builds.date,
            cheesy_frc_hours.scheduled_build_days.date,
            cheesy_frc_hours.scheduled_build_days.optional,
            cheesy_frc_hours.scheduled_build_days.starts_at,
            cheesy_frc_hours.scheduled_build_days.ends_at,
            timed_build_attendance.attended_seconds
        ORDER BY build_date ASC
), student_build_info AS (
    SELECT
        COUNT(IF(finalized AND required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(finalized AND attended AND required, 1, NULL)) AS required_attended_count,
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
        #{TIMED_BUILD_ATTENDANCE_CTE},
        lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
                    OR (#{optional_build_case("build_days.build_date")}) = 0
                )
        )
    SELECT
        filtered_build_days.build_date,
        students.id AS student_id,
        #{build_attended_case} AS attended,
        #{build_finalized_case} AS finalized,
        CASE
            WHEN (#{optional_build_case("filtered_build_days.build_date")}) = 1 THEN 0
            ELSE 1
        END AS required,
        MAX(NOT ISNULL(cheesy_frc_hours.excused_sessions.date)) AS excused
    FROM
        filtered_build_days CROSS JOIN cheesy_frc_hours.students
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
        LEFT JOIN timed_build_attendance ON timed_build_attendance.build_date=filtered_build_days.build_date
            AND timed_build_attendance.student_id=students.id
        LEFT JOIN cheesy_frc_hours.lab_sessions ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = filtered_build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id=cheesy_frc_hours.students.id
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id=cheesy_frc_hours.students.id
            AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
        GROUP BY
            filtered_build_days.build_date,
            students.id,
            cheesy_frc_hours.optional_builds.date,
            cheesy_frc_hours.scheduled_build_days.date,
            cheesy_frc_hours.scheduled_build_days.optional,
            cheesy_frc_hours.scheduled_build_days.starts_at,
            cheesy_frc_hours.scheduled_build_days.ends_at,
            timed_build_attendance.attended_seconds
        ORDER BY build_date ASC
), student_build_info AS (
    SELECT
        COUNT(IF(finalized AND required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(finalized AND attended AND required, 1, NULL)) AS required_attended_count,
        COUNT(IF(attended, 1, NULL)) AS total_attended_count,
        COUNT(IF(finalized AND required AND NOT attended AND NOT excused, 1, NULL)) AS unexcused_count,
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
        #{TIMED_BUILD_ATTENDANCE_CTE},
        lab_build_days AS (SELECT DISTINCT #{utc_to_local_date("time_in")} AS build_date FROM cheesy_frc_hours.lab_sessions WHERE NOT excluded_from_total),
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
    SELECT
        filtered_build_days.build_date,
        #{build_attended_case} AS attended,
        #{build_finalized_case} AS finalized,
        CASE
            WHEN (#{optional_build_case("filtered_build_days.build_date")}) = 1 THEN 0
            ELSE 1
        END AS required,
        MAX(NOT ISNULL(cheesy_frc_hours.excused_sessions.date)) AS excused
    FROM
        filtered_build_days
        LEFT JOIN cheesy_frc_hours.optional_builds ON cheesy_frc_hours.optional_builds.date=filtered_build_days.build_date
        LEFT JOIN cheesy_frc_hours.scheduled_build_days ON cheesy_frc_hours.scheduled_build_days.date=filtered_build_days.build_date
        LEFT JOIN timed_build_attendance ON timed_build_attendance.build_date=filtered_build_days.build_date
            AND timed_build_attendance.student_id = ?
        LEFT JOIN cheesy_frc_hours.lab_sessions ON #{utc_to_local_date("cheesy_frc_hours.lab_sessions.time_in")} = filtered_build_days.build_date
            AND cheesy_frc_hours.lab_sessions.student_id = ?
            AND NOT cheesy_frc_hours.lab_sessions.excluded_from_total
        LEFT JOIN cheesy_frc_hours.excused_sessions ON cheesy_frc_hours.excused_sessions.student_id = ?
            AND cheesy_frc_hours.excused_sessions.date=filtered_build_days.build_date
        GROUP BY
            filtered_build_days.build_date,
            cheesy_frc_hours.optional_builds.date,
            cheesy_frc_hours.scheduled_build_days.date,
            cheesy_frc_hours.scheduled_build_days.optional,
            cheesy_frc_hours.scheduled_build_days.starts_at,
            cheesy_frc_hours.scheduled_build_days.ends_at,
            timed_build_attendance.attended_seconds
    ORDER BY build_date ASC
), attendance_summary AS (
    SELECT
        COUNT(IF(finalized AND required AND (NOT excused OR (excused AND attended)), 1, NULL)) AS required_count,
        COUNT(IF(finalized AND attended AND required, 1, NULL)) AS required_attended_count,
        COUNT(IF(attended, 1, NULL)) AS total_attended_count,
        COUNT(IF(finalized AND required AND NOT attended AND NOT excused, 1, NULL)) AS unexcused_count
    FROM build_info
)

SELECT * FROM attendance_summary;
"""
