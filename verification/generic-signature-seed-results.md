# GenericSignature seed verification — 2026-11-23

- Console build passed (existing NU1902/NU1903 dependency warnings).
- SeedAsync completed twice against both configured test databases.
- tools/Verify-GenericSignatureSeed.ps1 passed after both runs, including exact
  process/day counts, trusted/enabled FK checks, archive-edge/FK matching,
  job reset, valid sample JSON, and absence of ArchiveScenarioTest/configuration.
- Archive job IDs remained 138 (nito_superDb) and 139 (nito_SomeApps).
- Each database: 9 tables, 82,912 rows, 8,130 processes, 1,361 populated days.
- Date range: 2023-01-01 through 2026-11-23. One root job and six archive edges per database.

| Table | Rows per database |
|---|---:|
| Processes | 8130 |
| AutentiProcesses | 7691 |
| AutentiRecipients | 18183 |
| CallProcesses | 4453 |
| EkdProcesses | 7691 |
| EkdProcessHistories | 18183 |
| ProcessData | 18577 |
| ProcessTypes | 2 |
| EkdStatuses | 2 |

Tests cover model creation and repeatable reseeding, not a full SSIS archive run
of all days since 2023. Existing unrelated schemas and jobs were outside the
seed deletion predicates. Package.dtsx was not modified.
