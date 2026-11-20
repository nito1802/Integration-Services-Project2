# Script Task variable lock fix

Job Script Tasks now capture exceptions inside their own entry point. They record
JobFailed and JobError and return success so the existing failure guards can skip
processing and reach Save job result. Their nested OnError Script Tasks are removed.
SQL and process task error handlers remain. Variable declarations are derived from
literal variable accesses in the generated C# source, including the catch block.

Verified with Windows PowerShell:

- `tools/Build-Package.ps1`: SQL Server 2022 package and embedded assemblies built.
- `tools/Build-Package.ps1 -CompatibilityTest`: compatibility package built.
- `tools/Verify-ScriptErrorHandling.ps1`: all nine guarded scripts have no nested
  handlers; variable declarations match embedded source; existing ZIP records a
  failure without FireError, preserves the file, and returns through guarded flow;
  source deletion retains its JobFailed guard; next job resets failure successfully.
- `tools/Verify-ArchivePaths.ps1`: month names, database separation, encoding,
  folder collisions and ZIP collisions passed.

The error-handling test executes the embedded C# with a substitute host. It does
not reproduce SSIS variable locking or execute the complete control flow.
Full database verification could not start: Create-TestDatabase.ps1 failed during
System.Data.SqlClient.SqlConnection type initialization in this environment.
A full SSIS runtime test with a pre-existing ZIP is still required before rollout.
No deployment or production database changes were performed.
