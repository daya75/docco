-- Confirm current geography values for the manual locations and disputed IDs
SELECT
    School_location_AGEID,
    AGEID,
    IsPrimaryLocation,
    `IGas.Latitude` AS latitude,
    `IGas.Longitude` AS longitude,
    `SA12021.SA1_CODE21` AS abs_sa1
FROM pr_dap_efs.business_sdpt_nongov_census.Schools_Geography_2026
WHERE CAST(School_location_AGEID AS BIGINT) IN (
    58021, 87943, 87945, 87946, 87947, 87948,
    88366, 88367, 89438, 89856, 89910, 89911,
    89912, 89914, 89927, 89928, 41951, 42395
);

-- Recompute FTE for location 89911 from its source rows
SELECT
    location_ageid,
    education_type,
    overseas_student,
    SUM(CAST(fte AS DOUBLE) * CAST(headcount AS DOUBLE)) AS source_fte
FROM pr_dap_efs.efs_gold.ngc_student_cohort_extract
WHERE CalendarYear = 26
  AND CAST(location_ageid AS BIGINT) = 89911
GROUP BY location_ageid, education_type, overseas_student
ORDER BY education_type, overseas_student;