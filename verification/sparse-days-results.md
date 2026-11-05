# Sparse archive days verification — 2026-10-27

- Production and compatibility packages rebuilt successfully.
- Archive-path regression test passed (empty days/years create no directories).
- Isolated LocalDB fixture: eligible Orders on 2020-02-03 and 2025-01-15, retention 50 days. Exactly two daily iterations, skipping all empty days and stopping before the retention cutoff.
- Actual SQL Task parameter/result bindings, CSV writer, ZIP content and row/key checks passed: 3508 archived CSV rows; 4 source rows retained including a row inserted after the daily snapshot.
- Expected invalid-column job recorded an error; following jobs succeeded.
- Production XML checked: calendar AssignExpression absent, Find next archive day task present.
- Test invokes native tasks individually using the compatibility runtime. Full scheduler/event-handler execution requires SSDT; SQL Server 2025 standalone runtime could not instantiate Application on this machine.
- Test fixture/output: verification/20261027_084410.
