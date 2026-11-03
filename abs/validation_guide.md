# NSSC 2026 Validation Guide

**Date:** 4 November 2026  
**Purpose:** Independently validate the Table 1, Table 2, and EDITS outputs and check key notebook assumptions.

Run the Databricks SQL checks in [`validation_queries.sql`](validation_queries.sql) against the same 2026 Delta tables used by the notebooks. Confirm the table and column names first if your environment differs.

## Run Order

1. **Table 1 school-type counts** — Run Query 1 to compare the saved Table 1 totals with the figures cited in the response letter. A match means zero differences. The current exports report Primary 1,426, Secondary 376, Combined 943, and Special 208, so expect differences against the letter’s 1,430, 511, 955, and 57.
2. **Affiliation mapping and grain** — Run Queries 2–3. Confirm that affiliation code 2 (Anglican) is present, that the source labels map as intended, that there are no conflicting school/location classifications, and that the school-versus-location counting grain is correct.
3. **EDITS against Tables 1 and 2** — Run Query 4. It independently rebuilds each non-total EDITS cell from the two input tables. Expect no numeric differences. A label-only mismatch for `Aboriginal and/or Torres Strait Islander` should be corrected in the export; do not treat it as a numeric mismatch.
4. **EDITS arithmetic** — Run Query 5. Check that each jurisdiction total equals Catholic plus Independent, and that each Australia total equals the sum of jurisdictions. Expect no returned rows.
5. **Table 2 input quality** — Run Queries 6–7. Check for invalid state, affiliation, sex, Indigenous-status, attendance, or grade values, negative/null measures, and source measures that could be silently converted to zero. Investigate any returned rows.
6. **DOB and related tables** — Use Query 8 to discover available DOB fields and the FFPOS/Remoteness table names. The DOB impact query is a template and requires the affected-location list plus the original and stored DOB fields.

## How to Interpret Results

The current saved CSV exports were independently reconciled: **891 source-derived numeric EDITS cells matched** the current Table 1 and Table 2 exports. Aggregate totals also matched: 2,953 schools, 1,573,743 enrolments, and 1,572,983 FTE.

That confirms internal numeric consistency between the current exports. It does not confirm that the Table 1 school-type breakdown matches the response letter or the separate validation CSV. Both references retain a total of 2,953 schools but report different type allocations. Resolve that classification discrepancy before treating the submission as validated.

The Table 1 notebook’s saved output reports its join and grand totals reconcile. The SQL checks independently test the category and affiliation breakdowns. The Table 2 creation logic is not included in this workspace, so these checks validate the available Table 2 output and its consistency with EDITS, not its upstream derivation.

## Validation Criteria

- Table 1 type counts and affiliation mapping match the agreed authoritative reference.
- No unintended duplicates or conflicts exist at the school/location join grain.
- Query 4 returns no numeric differences for the non-total EDITS cells.
- Query 5 returns no arithmetic differences.
- Query 6 returns no invalid Table 2 dimension or measure rows; Query 7 shows no unreviewed null, blank, or malformed source measures.
- Any label differences, especially the Indigenous category typo in the CSV export, are corrected separately from numeric reconciliation.
