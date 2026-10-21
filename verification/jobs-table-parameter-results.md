# Configurable jobs table — 2026-10-21

Added package parameter ArchiveJobsTable (default Archive.ArchiveJobs). Prepare job queries validates two-part schema.table input, quotes both identifiers and builds SELECT/start/result SQL strings. All database work remains in the existing Execute SQL Tasks. Spaces and bracket-quoted input are supported; dots within individual identifier names are not supported. The configured jobs database remains selected by ArchiveJobsConnectionString.

CreateArchiveJobs.sql now configures @SchemaName and @TableName at the top, checks that the schema already exists, quotes identifiers with QUOTENAME, and creates only the table. Re-running preserves existing rows and columns. No CREATE SCHEMA is issued. The anonymous primary-key constraint avoids collisions between multiple configured jobs tables in the same schema.

Verify-JobsTableParameter passed in isolated fixture 20261021_100104. It creates dbo.[Archive jobs] with the real creation script, copies job configuration, drops the default Archive.ArchiveJobs to detect accidental hardcoded references, re-runs the DDL and verifies four rows remain. Missing-schema input is rejected without creating that schema. Native SQL/source-host read-failure test then records Error for failed jobs and Success for subsequent jobs in the custom table.

Default-table compatibility passed in isolated fixture 20261021_100134: 3508 eligible rows archived and 3 source rows retained. Both production and compatibility packages rebuilt, with matching embedded sources and variable-based queries for all three jobs-table operations. Full scheduler/process-task verification still requires SSDT as documented in the other verification reports. EF/Console mapping remains independent of this package parameter.
