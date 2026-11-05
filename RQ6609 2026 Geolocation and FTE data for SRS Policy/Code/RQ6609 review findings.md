# RQ6609 Review Findings

Review date: 2026-11-05

## Scope and conclusion

Reviewed the current notebook and its saved outputs, the final Excel workbook and raw-data CSV, the manual-coordinate workbook, the SA1 lookup CSV/XLSX, the October 9 boundary-tag archive, archived October deliverables, and the supplied government enrolment CSV.

The final Excel data table contains 10,493 rows and matches the accompanying `RQ6609 raw data.csv` on all eight exported fields. The CSV also contains `year=2026`; the Excel data table omits that field, while the notebook's final dataframe has nine fields including `year`. Saved notebook validations report nine columns, no null or duplicate location IDs, one year (2026), and FTE totals of 4,111,379.71 funded and 24,532.30 FFPOS.

This confirms consistency between the final workbook and raw-data CSV, not correctness against live source tables. Notebook code cells have execution count 0 despite saved outputs, so the output provenance cannot be established from this notebook copy. No Databricks source query was run during this review.

## Findings

### Geography and SA1 lookup versions

- `Locations by SA1 2021.xlsx` has an embedded modified date of 2026-10-09 and 3,568 locations. The supplied boundary-tag archive contains `SSSoP_BoundaryTagResult_2026-10-09.csv`, also with 3,568 rows.
- `Locations by SA1 2021.csv` has 3,584 rows. Its 16 location IDs absent from the older XLSX are exactly the 16 entries in `RQ6609 - manually updated long_lat.xlsx`; all 16 appear in the current final workbook. This supports the interpretation that the XLSX is an earlier snapshot.
- The 12 manual coordinates that differ from the current final workbook agree with the corresponding coordinates in the CSV to within 0.000001 degrees. Four manual coordinates match the final workbook. However, the CSV is not an independent authority for the full dataset: for 3,576 shared IDs, it differs from the final workbook on 1,947 latitudes, 1,950 longitudes, and 811 SA1 codes. The current notebook takes geography from `Schools_Geography_2026`; validate against that source before certifying those coordinate changes.
- For locations 41951 and 42395, the October 9 boundary-tag file contains the older coordinates and blank SA1 values. The current final workbook and lookup CSV contain newer coordinates and nonblank SA1 values. Archived October 31 output still has the older coordinates. This is consistent with a later geography update, but the live geography table should be checked to confirm the final values.

### FTE at location 89911

The manual-coordinate workbook and October 31 archived output show funded FTE 15. The current final workbook shows 16. The notebook's saved non-government aggregate also reports total FTE 16.0, distance-education FTE 0.0, FFPOS FTE 0.0, and funded FTE 16.0. The supplied government enrolment CSV has no rows for school 89909 or locations 89910-89914. The current value therefore appears to come from the non-government cohort table, but must be checked against that table because the saved cell output is not an executed result in this notebook copy.

### Rows with zero output FTE

The saved intermediate tables contain 3,584 non-government and 6,947 government location rows. There is no location-ID overlap. The final validation reports 10,493 rows, 38 fewer than the 10,531 input rows. The saved intermediates contain eight non-government and 30 government rows where both `funded_fte` and `ffpos_fte` are zero. The notebook converts those zeros to nulls and drops the rows. These may represent distance-education-only locations; decide whether the requested open-school output should retain such locations with zero values or explicitly exclude them.

### Notebook validation logic

- The duplicate-removal loop drops duplicates as soon as any compared column has no differences, rather than only after confirming all compared fields agree. Saved outputs show no duplicate source locations in this run, so the issue was not triggered, but the logic remains unsafe for future data.
- Column-count comments say 18/21 although the actual output has nine columns.
- The notebook builds `schools_df` in memory and does not write a persistent table or file.

## Source queries to close the review

Run in Databricks and compare the results with the final workbook:

```sql
-- Current EFS geography values for manually updated and disputed locations
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

-- Recompute cohort FTE inputs for location 89911
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
```

## Review status

Workbook-to-CSV consistency: verified. Geography and SA1 source values: not independently verified against the live source table. Location 89911 FTE: supported by saved notebook output, pending source-table confirmation. Inclusion of 38 zero-output-FTE locations: requires a business-rule decision.
