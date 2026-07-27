# 13 — Data validators

**What to build:** The database validates itself. Cross-entity invariants — quest starters that exist, objectives referencing real IDs, parent/child consistency, spawn areas that resolve — run here, against data this repo owns, with no consumer checkout required.

This moves the single heaviest job out of Questie's CI.

**Blocked by:** 04, 12

**Status:** ready-for-agent

- [ ] The existing invariant checks are moved across and run against loaded entity data
- [ ] Checks needing zone lookups resolve them from support data owned here
- [ ] Validation runs per flavor and exits non-zero on failure
- [ ] Failures identify the offending entity and field clearly enough to write a correction from
- [ ] Validation runs against corrected data, so a correction that breaks an invariant is caught
- [ ] Diagnostic output is retained as an artifact for triage
