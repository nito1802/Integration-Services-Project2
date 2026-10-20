# Daily CSV / ZIP verification — 2026-10-20

Both the normal package and compatibility package build successfully. Static inspection confirms that `Create daily ZIP` and `Test daily ZIP` are Execute Process Tasks, with executable and argument expressions and OnError handlers. Script Tasks do not start a compression process.

The suite `tools/Verify-DailyArchive.ps1` uses isolated LocalDB databases, native Execute SQL Tasks, production C# sources with a substitute host, and real 7-Zip processes configured from the process tasks. Results:

| Scenario | Evidence directory | Outcome |
|---|---|---|
| Default limit 1000, 3508 eligible rows | `20261020_141842` | Passed; 3 retained source rows, exact order keys, CSV headers, ZIP entries, daily boundaries, no loose CSV after success. |
| Retry | `20261020_141842/native-retry-result.txt` | Passed; no empty CSV/ZIP generated. |
| Limit 37, dates distributed across 20 days | `20261020_141859` | Passed; 3508 rows archived, per-file limit and daily boundaries verified. |
| CSV write failure | `20261020_141932` | Passed; failed batch not deleted, later jobs succeed. |
| DELETE failure | `20261020_141937` | Passed; original CSV retained, later jobs succeed. |
| ZIP creation failure (7-Zip exit 7) | `20261020_141946` | Passed; CSV retained, later day skipped, job Error, later jobs succeed. |
| ZIP test failure (7-Zip exit 7) | `20261020_141954` | Passed; CSV retained alongside ZIP, job Error, later jobs succeed. |

Failed jobs preserve their previous successful-processing timestamp. The fixture includes a missing date column and an empty table; these produce Error and Success respectively.

## Runtime limitation

A real Execute Process Task was attempted against an isolated fixture (`20261020_140936`), but this workstation's runtime rejects it outside SSDT with the Standard Edition SSIS requirement. The default verifier consequently uses a test-only process host to launch the configured executable/arguments; production compression remains exclusively in Execute Process Tasks. Full package scheduling, loop expressions and automatic OnError dispatch still require F5 in Visual Studio / SSDT or an appropriately licensed SSIS runtime. These have not been claimed as tested end to end.

## Date-only names and collision protection

The package was rebuilt with `YYYY_MM_DD.zip` and `YYYY_MM_DD_part1.csv`, `part2.csv`, etc. The complete suite passed again:

- Default limit 1000 and empty retry: `20261020_143946`.
- Limit 37 / 20 days: `20261020_143958`.
- Write / delete / ZIP / ZIP test failures: `20261020_144020`, `20261020_144027`, `20261020_144033`, `20261020_144039`.
- Existing day folder: `20261020_144047`.
- Existing day ZIP: `20261020_144054`.

Both collision cases stop the affected job before batch export/deletion, preserve existing content byte for byte, retain all 2506 eligible order rows, and allow subsequent jobs to complete. Tests also assert exact filename patterns inside the ZIPs. Embedded production scripts match source files. The SSDT/runtime limitation above still applies.
