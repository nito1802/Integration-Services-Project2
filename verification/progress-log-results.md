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
