# Details and summary logs — verification 2026-11-23

LogFolder defaults to C:\ArchiveLogs. Each run creates one shared prefix and:
- _details.txt: existing detailed SQL/script/CSV/ZIP events retained.
- _summary.txt: RUN START/END, JOB START/END, TABLE START/END.

TABLE END measures a member/day from preparation through CSV and verified ZIP.
It excludes the later group deletion; JOB END includes deletion and cleanup.
Times use monotonic Stopwatch ticks, elapsedMs and readable duration.

Validation:
- Package generation and SQL Server 2022 ISPAC build passed.
- ISPAC: 82 Script Tasks, VSTA and runtime references 16.
- Sharing test passed: concurrent writers appended 201 complete Unicode lines
  to each file while both readers stayed open. I/O failures became warnings.
- SSISDB 60: Success; table/day, job and run timings verified, including empty job.
- SSISDB 62: ZIP interruption (-1073741510); TABLE END Error, JOB END Error,
  RUN END Error; source preserved and subsequent jobs successful.
- SSISDB 64: SQL delete failure; transaction rolled back, source preserved,
  SQL error retained in details, JOB END/RUN END Error in summary.
- SSISDB 66: Orders -> OrderLines -> LineDetails; per-table/day timing,
  including empty child days; related rows deleted correctly, recent rows kept.
- All tests verified matching log prefixes, retained earlier files, exactly
  three JOB END records, positive run time covering summed job durations.
- No variable deadlocks. SQL event loggers do not acquire summary/timer state.
- git diff --check passed.

Final ISPAC SHA256:
70D201BAEA25E248DFF52F2D31FE54CBFEFFC8D4C4AE29F22958A9D9264CD069

Built artifact: artifacts/sql2022/Archive.Sql2022.ispac.
Tests deployed only to the isolated ArchiveFailureTests project and fixture
SQL databases. The regular SQL Agent job was not redeployed.

## Update 2026-11-23: independent log switches

- Replaced LogFolder with LogPath; existing configured source path preserved.
- Parameters end with LogPath, DetailsLog, Summarylog in source package,
  dtproj metadata and final ISPAC. SSDT output is reordered after its serialization.
- DetailsLog/Summarylog are Boolean and default False. Boolean metadata uses
  numeric serialization accepted by SSDT. LogPath default is C:\ArchiveLogs.
- Both False: no directory validation/creation, no log files; SQL log handlers disabled.
- SSISDB 70: default False/False, success, no directory or log files created.
- SSISDB 72: details only, success, only details file created.
- SSISDB 74: summary only with related chain, success, only summary file created.
- SSISDB 76: both logs plus SQL delete failure, both logs and error summaries
  present, rollback/source preservation and following jobs verified.
- No variable deadlocks in any mode.
- LittleSeedAsync rerun and verified in nito_superDb and nito_SomeApps:
  50 processes each, 12 dates in 2023/2024, all related records and 6 archive edges.
- No actual source-data archiving was run after reseeding; verification uses fixtures.

Current ISPAC SHA256:
17E1825FF66D300F71B8BA8070C80785DBED12D74BD7E3B2A5BE62CD63A096CD
