-- Databricks SQL checks for the issues in response.md.
-- Run against the same 2026 Delta tables used by the notebooks.
-- The 2025 Table 1 name below assumes the matching year-suffixed table exists.


-- 1. Reproduce the school-type totals cited in the review letter.
-- Differences from the letter should be investigated before resubmission.
WITH actual AS (
    SELECT
        year,
        CASE schooltype
            WHEN 1 THEN 'Primary'
            WHEN 2 THEN 'Secondary'
            WHEN 3 THEN 'Combined'
            WHEN 4 THEN 'Special'
            ELSE CONCAT('Unknown code ', CAST(schooltype AS STRING))
        END AS school_type,
        SUM(school_count) AS actual_count
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2025
    WHERE year = 2025
    GROUP BY year, schooltype

    UNION ALL

    SELECT
        year,
        CASE schooltype
            WHEN 1 THEN 'Primary'
            WHEN 2 THEN 'Secondary'
            WHEN 3 THEN 'Combined'
            WHEN 4 THEN 'Special'
            ELSE CONCAT('Unknown code ', CAST(schooltype AS STRING))
        END AS school_type,
        SUM(school_count) AS actual_count
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2026
    WHERE year = 2026
    GROUP BY year, schooltype
), expected AS (
    SELECT * FROM VALUES
        (2025, 'Primary', 1427),
        (2025, 'Secondary', 380),
        (2025, 'Combined', 933),
        (2025, 'Special', 196),
        (2026, 'Primary', 1430),
        (2026, 'Secondary', 511),
        (2026, 'Combined', 955),
        (2026, 'Special', 57)
    AS v(year, school_type, letter_count)
)
SELECT
    COALESCE(e.year, a.year) AS year,
    COALESCE(e.school_type, a.school_type) AS school_type,
    e.letter_count,
    a.actual_count,
    a.actual_count - e.letter_count AS difference
FROM expected e
FULL OUTER JOIN actual a
    ON a.year = e.year AND a.school_type = e.school_type
ORDER BY year, school_type;


-- 2. Confirm affiliation codes and locate state/type cells with no Anglican
-- records. Expected source codes: 2=Anglican, 3=Catholic, 4=Other.
SELECT
    year,
    state,
    affiliation,
    SUM(school_count) AS schools,
    COUNT(*) AS aggregate_rows
FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2026
GROUP BY year, state, affiliation
ORDER BY year, state, affiliation;

SELECT
    year,
    state,
    schooltype,
    SUM(school_count) AS schools
FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2026
WHERE affiliation = 2
GROUP BY year, state, schooltype
ORDER BY year, state, schooltype;

-- The Table 1 mapper sends all unmatched or NULL affiliation text to code 4.
-- Review these raw labels to ensure that code 4 truly means Other.
SELECT
    LOWER(TRIM(CAST(Affiliation AS STRING))) AS raw_affiliation,
    CASE
        WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%non-anglican%' THEN 4
        WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%anglican%' THEN 2
        WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%non-catholic%' THEN 4
        WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%catholic%' THEN 3
        ELSE 4
    END AS mapped_affiliation,
    COUNT(DISTINCT NAMED_STRUCT(
        'school_ageid', CAST(AGEID AS STRING),
        'location_ageid', CAST(School_Location_AGEID AS STRING)
    )) AS school_locations
FROM pr_dap_efs.business_sdpt_nongov_census.schools_geography_2026
GROUP BY LOWER(TRIM(CAST(Affiliation AS STRING)))
ORDER BY mapped_affiliation, raw_affiliation;

-- Any returned row is a school/location with conflicting derived affiliation.
WITH mapped AS (
    SELECT DISTINCT
        CAST(AGEID AS STRING) AS school_ageid,
        CAST(School_Location_AGEID AS STRING) AS location_ageid,
        CASE
            WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%non-anglican%' THEN 4
            WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%anglican%' THEN 2
            WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%non-catholic%' THEN 4
            WHEN LOWER(TRIM(CAST(Affiliation AS STRING))) LIKE '%catholic%' THEN 3
            ELSE 4
        END AS mapped_affiliation
    FROM pr_dap_efs.business_sdpt_nongov_census.schools_geography_2026
    WHERE AGEID IS NOT NULL AND School_Location_AGEID IS NOT NULL
)
SELECT school_ageid, location_ageid, COUNT(DISTINCT mapped_affiliation) AS affiliation_count
FROM mapped
GROUP BY school_ageid, location_ageid
HAVING COUNT(DISTINCT mapped_affiliation) > 1;


-- 3. Check whether Table 1's school-level grain (school_ageid) differs from
-- the number of school/location pairs in the student extract.
WITH source AS (
    SELECT DISTINCT
        CAST(school_ageid AS STRING) AS school_ageid,
        CAST(location_ageid AS STRING) AS location_ageid
    FROM pr_dap_efs.efs_gold.ngc_student_cohort_extract
    WHERE TRY_CAST(CalendarYear AS INT) = 26
), source_counts AS (
    SELECT
        COUNT(DISTINCT school_ageid) AS distinct_schools,
        COUNT(DISTINCT NAMED_STRUCT(
            'school_ageid', school_ageid,
            'location_ageid', location_ageid
        )) AS distinct_school_locations
    FROM source
), output_count AS (
    SELECT SUM(school_count) AS table_1_schools
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2026
    WHERE year = 2026
)
SELECT * FROM source_counts CROSS JOIN output_count;

-- Inspect schools represented by multiple locations; review whether the
-- Table 1 definition should count schools or locations for these records.
SELECT
    CAST(school_ageid AS STRING) AS school_ageid,
    COUNT(DISTINCT CAST(location_ageid AS STRING)) AS location_count
FROM pr_dap_efs.efs_gold.ngc_student_cohort_extract
WHERE TRY_CAST(CalendarYear AS INT) = 26
GROUP BY CAST(school_ageid AS STRING)
HAVING COUNT(DISTINCT CAST(location_ageid AS STRING)) > 1
ORDER BY location_count DESC, school_ageid;


-- 4. Recalculate every non-total EDITS cell directly from Table 1 and Table 2.
-- This uses the same published EDITS grouping rule: affiliation 3=Catholic;
-- affiliation 2 or 4=Independent. FTE is rounded to one decimal in the output.
WITH table_1 AS (
    SELECT
        CASE state
            WHEN 1 THEN 'NSW' WHEN 2 THEN 'VIC' WHEN 3 THEN 'QLD'
            WHEN 4 THEN 'SA' WHEN 5 THEN 'WA' WHEN 6 THEN 'TAS'
            WHEN 7 THEN 'NT' WHEN 8 THEN 'ACT'
        END AS state_territory,
        CASE affiliation
            WHEN 3 THEN 'Catholic'
            WHEN 2 THEN 'Independent'
            WHEN 4 THEN 'Independent'
        END AS school_affiliation,
        CASE schooltype
            WHEN 1 THEN 'Primary' WHEN 2 THEN 'Secondary'
            WHEN 3 THEN 'Combined' WHEN 4 THEN 'Special'
        END AS category,
        school_count
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_1_2026
    WHERE year = 2026
),
table_2 AS (
    SELECT
        CASE state
            WHEN 1 THEN 'NSW' WHEN 2 THEN 'VIC' WHEN 3 THEN 'QLD'
            WHEN 4 THEN 'SA' WHEN 5 THEN 'WA' WHEN 6 THEN 'TAS'
            WHEN 7 THEN 'NT' WHEN 8 THEN 'ACT'
        END AS state_territory,
        CASE affiliation
            WHEN 3 THEN 'Catholic'
            WHEN 2 THEN 'Independent'
            WHEN 4 THEN 'Independent'
        END AS school_affiliation,
        sex,
        stud_typ,
        LOWER(TRIM(CAST(fp_ind AS STRING))) AS attendance_text,
        TRY_CAST(NULLIF(TRIM(CAST(grade AS STRING)), '') AS INT) AS grade_code,
        enrolments,
        fte
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_2_2026
    WHERE year = 2026
),
expected AS (
    SELECT
        'School Count' AS counting_unit,
        'School Level' AS classifications,
        category,
        state_territory,
        school_affiliation,
        SUM(school_count) AS expected_value
    FROM table_1
    WHERE state_territory IS NOT NULL AND school_affiliation IS NOT NULL
      AND category IS NOT NULL
    GROUP BY category, state_territory, school_affiliation

    UNION ALL

    SELECT 'Student Count (including students at special schools)', 'Sex',
        CASE sex WHEN 1 THEN 'Male' WHEN 2 THEN 'Female' WHEN 3 THEN 'Other'
            WHEN 9 THEN 'Not Stated/Inadequately described' END,
        state_territory, school_affiliation, SUM(enrolments)
    FROM table_2
    WHERE sex IN (1, 2, 3, 9) AND state_territory IS NOT NULL
      AND school_affiliation IS NOT NULL
    GROUP BY sex, state_territory, school_affiliation

    UNION ALL

    SELECT 'Student Count (including students at special schools)', 'Indigenous Status',
        CASE stud_typ WHEN 4 THEN 'Aboriginal and/or Torres Strait Islander'
            WHEN 0 THEN 'Non-Indigenous' WHEN 11 THEN 'Not-stated' END,
        state_territory, school_affiliation, SUM(enrolments)
    FROM table_2
    WHERE stud_typ IN (0, 4, 11) AND state_territory IS NOT NULL
      AND school_affiliation IS NOT NULL
    GROUP BY stud_typ, state_territory, school_affiliation

    UNION ALL

    SELECT 'Student Count (including students at special schools)', 'Attendance Status',
        CASE
            WHEN attendance_text IN ('full time', 'full-time', 'fulltime') THEN 'Full-time'
            WHEN attendance_text IN ('part time', 'part-time', 'parttime') THEN 'Part-time'
        END,
        state_territory, school_affiliation, SUM(enrolments)
    FROM table_2
    WHERE attendance_text IN ('full time', 'full-time', 'fulltime',
                              'part time', 'part-time', 'parttime')
      AND state_territory IS NOT NULL AND school_affiliation IS NOT NULL
    GROUP BY CASE
                 WHEN attendance_text IN ('full time', 'full-time', 'fulltime') THEN 'Full-time'
                 WHEN attendance_text IN ('part time', 'part-time', 'parttime') THEN 'Part-time'
             END,
             state_territory, school_affiliation

    UNION ALL

    SELECT 'Student Count (including students at special schools)', 'School Level',
        CASE WHEN grade_code IN (1, 2, 3, 4, 5, 6, 7, 9) THEN 'Primary'
             WHEN grade_code IN (10, 11, 12, 13, 14, 15, 16) THEN 'Secondary' END,
        state_territory, school_affiliation, SUM(enrolments)
    FROM table_2
    WHERE (grade_code IN (1, 2, 3, 4, 5, 6, 7, 9)
        OR grade_code IN (10, 11, 12, 13, 14, 15, 16))
      AND state_territory IS NOT NULL AND school_affiliation IS NOT NULL
    GROUP BY CASE WHEN grade_code IN (1, 2, 3, 4, 5, 6, 7, 9) THEN 'Primary'
                  WHEN grade_code IN (10, 11, 12, 13, 14, 15, 16) THEN 'Secondary' END,
             state_territory, school_affiliation

    UNION ALL

    SELECT 'Student FTE (including students at special schools)', 'Sex',
        CASE sex WHEN 1 THEN 'Male' WHEN 2 THEN 'Female' WHEN 3 THEN 'Other'
            WHEN 9 THEN 'Not Stated/Inadequately described' END,
        state_territory, school_affiliation, SUM(fte)
    FROM table_2
    WHERE sex IN (1, 2, 3, 9) AND state_territory IS NOT NULL
      AND school_affiliation IS NOT NULL
    GROUP BY sex, state_territory, school_affiliation

    UNION ALL

    SELECT 'Student FTE (including students at special schools)', 'Indigenous Status',
        CASE stud_typ WHEN 4 THEN 'Aboriginal and/or Torres Strait Islander'
            WHEN 0 THEN 'Non-Indigenous' WHEN 11 THEN 'Not-stated' END,
        state_territory, school_affiliation, SUM(fte)
    FROM table_2
    WHERE stud_typ IN (0, 4, 11) AND state_territory IS NOT NULL
      AND school_affiliation IS NOT NULL
    GROUP BY stud_typ, state_territory, school_affiliation

    UNION ALL

    SELECT 'Student FTE (including students at special schools)', 'Attendance Status',
        CASE
            WHEN attendance_text IN ('full time', 'full-time', 'fulltime') THEN 'Full-time'
            WHEN attendance_text IN ('part time', 'part-time', 'parttime') THEN 'Part-time'
        END,
        state_territory, school_affiliation, SUM(fte)
    FROM table_2
    WHERE attendance_text IN ('full time', 'full-time', 'fulltime',
                              'part time', 'part-time', 'parttime')
      AND state_territory IS NOT NULL AND school_affiliation IS NOT NULL
    GROUP BY CASE
                 WHEN attendance_text IN ('full time', 'full-time', 'fulltime') THEN 'Full-time'
                 WHEN attendance_text IN ('part time', 'part-time', 'parttime') THEN 'Part-time'
             END,
             state_territory, school_affiliation

    UNION ALL

    SELECT 'Student FTE (including students at special schools)', 'School Level',
        CASE WHEN grade_code IN (1, 2, 3, 4, 5, 6, 7, 9) THEN 'Primary'
             WHEN grade_code IN (10, 11, 12, 13, 14, 15, 16) THEN 'Secondary' END,
        state_territory, school_affiliation, SUM(fte)
    FROM table_2
    WHERE (grade_code IN (1, 2, 3, 4, 5, 6, 7, 9)
        OR grade_code IN (10, 11, 12, 13, 14, 15, 16))
      AND state_territory IS NOT NULL AND school_affiliation IS NOT NULL
    GROUP BY CASE WHEN grade_code IN (1, 2, 3, 4, 5, 6, 7, 9) THEN 'Primary'
                  WHEN grade_code IN (10, 11, 12, 13, 14, 15, 16) THEN 'Secondary' END,
             state_territory, school_affiliation
),
actual AS (
    SELECT
        e.Counting_Unit AS counting_unit,
        e.Classifications AS classifications,
        e.Categories AS category,
        cells.state_territory,
        cells.school_affiliation,
        cells.actual_value
    FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_edits_2026 e
    LATERAL VIEW STACK(
        16,
        'NSW', 'Catholic', CAST(e.NSW_Catholic AS DECIMAL(24,6)),
        'NSW', 'Independent', CAST(e.NSW_Independent AS DECIMAL(24,6)),
        'VIC', 'Catholic', CAST(e.VIC_Catholic AS DECIMAL(24,6)),
        'VIC', 'Independent', CAST(e.VIC_Independent AS DECIMAL(24,6)),
        'QLD', 'Catholic', CAST(e.QLD_Catholic AS DECIMAL(24,6)),
        'QLD', 'Independent', CAST(e.QLD_Independent AS DECIMAL(24,6)),
        'SA', 'Catholic', CAST(e.SA_Catholic AS DECIMAL(24,6)),
        'SA', 'Independent', CAST(e.SA_Independent AS DECIMAL(24,6)),
        'WA', 'Catholic', CAST(e.WA_Catholic AS DECIMAL(24,6)),
        'WA', 'Independent', CAST(e.WA_Independent AS DECIMAL(24,6)),
        'TAS', 'Catholic', CAST(e.TAS_Catholic AS DECIMAL(24,6)),
        'TAS', 'Independent', CAST(e.TAS_Independent AS DECIMAL(24,6)),
        'NT', 'Catholic', CAST(e.NT_Catholic AS DECIMAL(24,6)),
        'NT', 'Independent', CAST(e.NT_Independent AS DECIMAL(24,6)),
        'ACT', 'Catholic', CAST(e.ACT_Catholic AS DECIMAL(24,6)),
        'ACT', 'Independent', CAST(e.ACT_Independent AS DECIMAL(24,6))
    ) cells AS state_territory, school_affiliation, actual_value
    WHERE e.Categories <> 'Total'
)
SELECT
    COALESCE(x.counting_unit, a.counting_unit) AS counting_unit,
    COALESCE(x.classifications, a.classifications) AS classifications,
    COALESCE(x.category, a.category) AS category,
    COALESCE(x.state_territory, a.state_territory) AS state_territory,
    COALESCE(x.school_affiliation, a.school_affiliation) AS school_affiliation,
    ROUND(x.expected_value,
        CASE WHEN x.counting_unit LIKE 'Student FTE%' THEN 1 ELSE 0 END) AS expected_value,
    a.actual_value,
    a.actual_value - ROUND(x.expected_value,
        CASE WHEN x.counting_unit LIKE 'Student FTE%' THEN 1 ELSE 0 END) AS difference
FROM expected x
FULL OUTER JOIN actual a
    ON a.counting_unit = x.counting_unit
   AND a.classifications = x.classifications
   AND a.category = x.category
   AND a.state_territory = x.state_territory
   AND a.school_affiliation = x.school_affiliation
WHERE ABS(COALESCE(a.actual_value, 0) - COALESCE(
    ROUND(x.expected_value,
        CASE WHEN x.counting_unit LIKE 'Student FTE%' THEN 1 ELSE 0 END), 0
)) >= 0.0001
ORDER BY counting_unit, classifications, category, state_territory, school_affiliation;


-- 5. Check EDITS row-level total arithmetic independently of its cell values.
SELECT
    Counting_Unit,
    Classifications,
    Categories,
    State_Territory,
    State_Total,
    Catholic_Value + Independent_Value AS affiliation_sum,
    State_Total - Catholic_Value - Independent_Value AS difference
FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_edits_2026
LATERAL VIEW STACK(
    8,
    'NSW', NSW_TOTAL, NSW_Catholic, NSW_Independent,
    'VIC', VIC_TOTAL, VIC_Catholic, VIC_Independent,
    'QLD', QLD_TOTAL, QLD_Catholic, QLD_Independent,
    'SA', SA_TOTAL, SA_Catholic, SA_Independent,
    'WA', WA_TOTAL, WA_Catholic, WA_Independent,
    'TAS', TAS_TOTAL, TAS_Catholic, TAS_Independent,
    'NT', NT_TOTAL, NT_Catholic, NT_Independent,
    'ACT', ACT_TOTAL, ACT_Catholic, ACT_Independent
) t AS State_Territory, State_Total, Catholic_Value, Independent_Value
WHERE ABS(State_Total - Catholic_Value - Independent_Value) >= 0.0001;

SELECT
    Counting_Unit,
    Classifications,
    Categories,
    AUSTRALIA_TOTAL - (NSW_TOTAL + VIC_TOTAL + QLD_TOTAL + SA_TOTAL
        + WA_TOTAL + TAS_TOTAL + NT_TOTAL + ACT_TOTAL) AS total_difference,
    AUSTRALIA_Catholic - (NSW_Catholic + VIC_Catholic + QLD_Catholic + SA_Catholic
        + WA_Catholic + TAS_Catholic + NT_Catholic + ACT_Catholic) AS catholic_difference,
    AUSTRALIA_Independent - (NSW_Independent + VIC_Independent + QLD_Independent
        + SA_Independent + WA_Independent + TAS_Independent + NT_Independent
        + ACT_Independent) AS independent_difference
FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_edits_2026
WHERE ABS(AUSTRALIA_TOTAL - (NSW_TOTAL + VIC_TOTAL + QLD_TOTAL + SA_TOTAL
        + WA_TOTAL + TAS_TOTAL + NT_TOTAL + ACT_TOTAL)) >= 0.0001
   OR ABS(AUSTRALIA_Catholic - (NSW_Catholic + VIC_Catholic + QLD_Catholic + SA_Catholic
        + WA_Catholic + TAS_Catholic + NT_Catholic + ACT_Catholic)) >= 0.0001
   OR ABS(AUSTRALIA_Independent - (NSW_Independent + VIC_Independent + QLD_Independent
        + SA_Independent + WA_Independent + TAS_Independent + NT_Independent
        + ACT_Independent)) >= 0.0001;


-- 6. Find invalid Table 2 dimensions that the EDITS notebook is expected to
-- reject, including grade 8, unmapped attendance, and unknown status codes.
SELECT
    state,
    affiliation,
    sex,
    stud_typ,
    fp_ind,
    grade,
    COUNT(*) AS rows,
    SUM(enrolments) AS enrolments,
    SUM(fte) AS fte
FROM pr_dap_efs.business_sdpt_abs.nssc_ngs_table_2_2026
WHERE year = 2026
  AND (
      state IS NULL OR state NOT BETWEEN 1 AND 8
      OR affiliation IS NULL OR affiliation NOT IN (2, 3, 4)
      OR sex IS NULL OR sex NOT IN (1, 2, 3, 9)
      OR stud_typ IS NULL OR stud_typ NOT IN (0, 4, 11)
      OR fp_ind IS NULL OR LOWER(TRIM(CAST(fp_ind AS STRING))) NOT IN
          ('full time', 'full-time', 'fulltime', 'part time', 'part-time', 'parttime')
      OR TRY_CAST(NULLIF(TRIM(CAST(grade AS STRING)), '') AS INT) IS NULL
      OR TRY_CAST(NULLIF(TRIM(CAST(grade AS STRING)), '') AS INT) NOT IN
          (1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15, 16)
      OR enrolments IS NULL OR enrolments < 0
      OR fte IS NULL OR fte < 0
  )
GROUP BY state, affiliation, sex, stud_typ, fp_ind, grade
ORDER BY state, affiliation, grade;


-- 7. Check whether source headcount/FTE values are being silently turned into
-- zero by the Table 1 notebook's try_decimal() helper. Confirm the physical
-- column names with DESCRIBE TABLE before running this query.
SELECT
    COUNT(*) AS source_rows,
    SUM(CASE WHEN headcount IS NULL THEN 1 ELSE 0 END) AS null_headcount,
    SUM(CASE WHEN NULLIF(TRIM(CAST(headcount AS STRING)), '') IS NULL
             AND headcount IS NOT NULL THEN 1 ELSE 0 END) AS blank_headcount,
    SUM(CASE WHEN NULLIF(TRIM(CAST(headcount AS STRING)), '') IS NOT NULL
              AND TRY_CAST(headcount AS DECIMAL(24,6)) IS NULL
             THEN 1 ELSE 0 END) AS malformed_headcount,
    SUM(CASE WHEN fte IS NULL THEN 1 ELSE 0 END) AS null_fte,
    SUM(CASE WHEN NULLIF(TRIM(CAST(fte AS STRING)), '') IS NULL
             AND fte IS NOT NULL THEN 1 ELSE 0 END) AS blank_fte,
    SUM(CASE WHEN NULLIF(TRIM(CAST(fte AS STRING)), '') IS NOT NULL
              AND TRY_CAST(fte AS DECIMAL(24,6)) IS NULL
             THEN 1 ELSE 0 END) AS malformed_fte
FROM pr_dap_efs.efs_gold.ngc_student_cohort_extract
WHERE TRY_CAST(CalendarYear AS INT) = 26;


-- 8. DOB issue: first identify DOB and Indigenous-status fields and the exact
-- FFPOS/Remoteness table names. These are not specified in the notebooks.
SELECT table_schema, table_name, column_name, data_type
FROM pr_dap_efs.information_schema.columns
WHERE (table_schema = 'efs_gold'
       AND table_name = 'ngc_student_cohort_extract'
       AND LOWER(column_name) LIKE '%dob%')
   OR LOWER(table_name) LIKE '%ffpos%'
   OR LOWER(table_name) LIKE '%remoteness%'
ORDER BY table_schema, table_name, ordinal_position;

-- DOB impact template. Replace the three angle-bracket identifiers below:
--   <affected_86_locations> must contain distinct school_ageid/location_ageid
--   <raw_dob_column> must preserve the original MM/DD/YYYY text
--   <stored_dob_column> must be the date value submitted after ingestion
-- If the original date text is unavailable, the swapped-date impact cannot be
-- established from the parsed date alone; obtain the source file or audit log.
WITH affected_locations AS (
    SELECT DISTINCT
        CAST(school_ageid AS STRING) AS school_ageid,
        CAST(location_ageid AS STRING) AS location_ageid
    FROM <affected_86_locations>
), dob_rows AS (
    SELECT
        s.school_state AS state_territory,
        s.stud_typ AS indigenous_code,
        TRY_CAST(
            TRY_TO_TIMESTAMP(CAST(s.<raw_dob_column> AS STRING), 'M/d/yyyy')
            AS DATE
        ) AS corrected_dob,
        TRY_CAST(s.<stored_dob_column> AS DATE) AS stored_dob
    FROM pr_dap_efs.efs_gold.ngc_student_cohort_extract s
    INNER JOIN affected_locations l
        ON CAST(s.school_ageid AS STRING) = l.school_ageid
       AND CAST(s.location_ageid AS STRING) = l.location_ageid
    WHERE TRY_CAST(s.CalendarYear AS INT) = 26
)
SELECT
    state_territory,
    CASE indigenous_code
        WHEN 4 THEN 'Aboriginal and/or Torres Strait Islander'
        WHEN 0 THEN 'Non-Indigenous'
        WHEN 11 THEN 'Not-stated'
        ELSE CONCAT('Other code ', CAST(indigenous_code AS STRING))
    END AS indigenous_status,
    COUNT(*) AS students_at_affected_locations,
    SUM(CASE WHEN corrected_dob IS DISTINCT FROM stored_dob THEN 1 ELSE 0 END)
        AS records_with_dob_difference,
    SUM(CASE WHEN corrected_dob IS NULL THEN 1 ELSE 0 END)
        AS raw_dates_not_parseable_as_mmddyyyy
FROM dob_rows
GROUP BY state_territory, indigenous_code
ORDER BY state_territory, indigenous_status;

-- Confirm the supplied location list has 86 distinct entries and quantify
-- duplicate/missing IDs before using it in the DOB analysis.
SELECT
    COUNT(*) AS rows_in_location_list,
    COUNT(DISTINCT NAMED_STRUCT(
        'school_ageid', CAST(school_ageid AS STRING),
        'location_ageid', CAST(location_ageid AS STRING)
    )) AS distinct_school_locations,
    SUM(CASE WHEN school_ageid IS NULL OR location_ageid IS NULL THEN 1 ELSE 0 END)
        AS rows_missing_ids
FROM <affected_86_locations>;

-- 9. Sign-off is a document control requirement and has no SQL validation.