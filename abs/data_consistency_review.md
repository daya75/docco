# NSSC 2026 Table and EDITS Consistency Review

**Review date:** 4 November 2026  
**Scope:** Saved CSV exports and saved notebook outputs in this workspace. The source Databricks tables were not queried live.

## Conclusion

The exported EDITS numbers reconcile to the exported Table 1 and Table 2 data under the mappings implemented in the EDITS notebook. An independent aggregation of the CSVs found **0 numeric mismatches across 891 source-derived cells**. The aggregate totals also match:

| Measure | Source total | EDITS total | Result |
|---|---:|---:|---|
| Table 1 schools | 2,953 | 2,953 | Match |
| Table 2 enrolments | 1,573,743 | 1,573,743 | Match |
| Table 2 FTE | 1,572,983 | 1,572,983 | Match |

This confirms consistency between the files currently supplied; it does **not** resolve the differences from the review letter or the separate validation CSV.

## Table 1 School-Type Reconciliation

The exported Table 1 and EDITS school-count rows agree with each other but do not match either reference breakdown:

| School type | Table 1 CSV and EDITS | Response letter | Validation CSV |
|---|---:|---:|---:|
| Primary | 1,426 | 1,430 | 1,408 |
| Secondary | 376 | 511 | 479 |
| Combined | 943 | 955 | 1,009 |
| Special | 208 | 57 | 57 |
| **Total** | **2,953** | **2,953** | **2,953** |

The total is stable while the type allocation is not. Relative to the letter, the current exports are Primary -4, Secondary -135, Combined -12, and Special +151. The revised Table 1 notebook’s saved output is consistent with the exported Table 1 school-type allocation; it does not demonstrate that this allocation matches the letter or validation CSV.

## Affiliation

The Table 1 CSV contains all three affiliation codes:

| Code | Table 1 meaning | Schools |
|---:|---|---:|
| 2 | Anglican | 159 |
| 3 | Catholic | 1,757 |
| 4 | Other | 1,037 |

Therefore, the exported Table 1 does contain Anglican records, contrary to the statement that no affiliation 2 records are present. The EDITS notebook maps code 3 to Catholic and combines codes 2 and 4 as Independent. That yields 1,757 Catholic and 1,196 Independent schools in EDITS. The validation CSV instead reports 1,687 Catholic and 1,266 Independent schools, while retaining the same total of 2,953.

## Table 2 and EDITS

Table 2 source totals reconcile to EDITS, including student count by sex, Indigenous status, attendance, and school level, and FTE for the same classifications. The EDITS notebook’s saved outputs also report its internal cell and arithmetic validations passed.

There is a label discrepancy in the exported EDITS CSV: `Aborignal and/or Torres Strait Islander` is misspelled. The saved EDITS notebook output uses `Aboriginal and/or Torres Strait Islander`. The numeric comparison normalized that label for matching; correct the exported label before resubmission.

A national-total example shows why the validation CSV still needs attention: the current EDITS gives student counts of 840,356 Catholic and 733,387 Independent; the validation CSV gives 779,696 Catholic and 794,047 Independent. Both sum to 1,573,743, but the affiliation split differs.

## Recommended Follow-Up

1. Reconcile the 2026 school-type allocation against the source school/location records and agree on the governing classification rule, especially for Special and Special Assistance schools.
2. Reconcile affiliation mapping and the validation CSV’s Catholic/Independent splits with the Table 1 and Table 2 inputs.
3. Regenerate the EDITS export after the accepted Table 1 and affiliation decisions, and correct the Indigenous category label.
4. Review the separate DOB, FFPOS, and Remoteness issues independently; they are not validated by this numeric table reconciliation.

## Files Reviewed

- `data/6616949450_NSSC Table_1 2026_table_1 2026.csv`
- `data/6616949450_NSSC Table_2 2026_table_2 2026.csv`
- `data/6616949450_NSSC EDITS 2026 Non-government_NONGOV 2026 EDITS.csv`
- `data/EDITS 2026 Non-government validation_NONGOV 2026 EDITS VALIDATION.csv`
- `Revised Final Table1_2_11.ipynb`
- `nssc_ngs_edits_2026_complete_3_11 (1).ipynb`
