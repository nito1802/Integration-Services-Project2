# Execute SQL Tasks only — 2026-10-21

The production package and compatibility package build successfully. Static inspection confirms all 28 embedded Script Task sources match their current C# files, with no database connection acquisition, ChangeDatabase, SqlCommand, SqlBulkCopy or SQL execution APIs. Retired database Script Task implementations are replaced by explanatory comments; previous implementations remain in Git history.

Database operations are Execute SQL Tasks: Get Archive Jobs, Start archive job, Read table shape, Read table metadata, Get cutoff date, Find first day, Read archive batch, Delete exported batch, SetTableStatus.

ArchiveDb selects the current DatabaseName via its ConnectionString expression. RetainSameConnection is false. Database selection was verified with native Execute SQL Tasks against master, tempdb, the isolated fixture database, and master again. No C# changes database context.

C# prepares metadata/shape/first-day queries, transforms their returned DataSets, and builds the batch-delete SQL plus a parameter containing base64-encoded XML keys. The delete SQL task creates and populates its temporary key table, handles IDENTITY_INSERT, deletes by the exact key tuple, and returns its affected-row count within one task/session. C# retains CSV and file handling; ZIP creation/testing remain Execute Process Tasks.

## Test results

Full tools/Verify-DailyArchive.ps1 suite passed:

| Scenario | Evidence directory |
|---|---|
| Database routing, default limit 1000, empty retry | 20261021_080459 |
| Limit 37 across 20 days | 20261021_080515 |
| Composite key types / empty and control-character strings / empty and nonempty binary values | 20261021_080541 |
| CSV write failure | 20261021_080551 |
| DELETE failure | 20261021_080558 |
| ZIP creation failure | 20261021_080607 |
| ZIP test failure | 20261021_080616 |
| Existing day folder | 20261021_080625 |
| Existing day ZIP | 20261021_080633 |

Successful exports contained 3508 eligible rows, preserved exact order keys, and retained 3 noneligible source rows. Composite key coverage includes nvarchar, int, uniqueidentifier, varbinary, decimal, datetime, datetimeoffset, time and float. Both ordinary and key-type fixtures include IDENTITY order keys. Failure cases preserve the previous successful timestamp, retain required CSV files and allow later jobs to complete.

## Limits of verification

Tests execute native Execute SQL Task objects and production C# via a substitute script host. Error events and loop iteration are driven by the test host. ZIP executable/arguments are exercised through a test-only process host because the local runtime license blocks Execute Process Task outside SSDT. Full package scheduling and automatic event dispatch still require an F5 run in Visual Studio/SSDT or appropriately licensed SSIS runtime. No end-to-end scheduler run is claimed.

## SSDT adapter / debugger compatibility follow-up

The reported IDataAdapter error occurred in Read table metadata under SSDT. Its complete inner error was not supplied, so the exact provider failure remains unconfirmed. Metadata SQL is now one CTE/SELECT statement without external parameter binding; the table-name literal escapes apostrophes. Read archive batch also avoids parameterized Full result set execution: C# formats positive integer limits and invariant ISO datetime2 literals. All database operations remain Execute SQL Tasks.

The full LocalDB suite passed again: 20261021_082525 (routing, default export and retry), 20261021_082542 (37-record limit over 20 days), 20261021_082615 (key types), and failure fixtures through 20261021_082704. Both packages build and all Full result set tasks have zero external parameter bindings.

The subsequent ValidateAndRunDebugger/NullCheck stack concerns debugger launch before task execution. Inspection found stale project package VersionGUID/VersionBuild metadata. The builder now synchronizes this metadata, increments the current version instead of reverting to the backup version, and preserves package parameter identities. A real repeated rebuild confirmed unchanged parameter IDs and matching project/package metadata. This inconsistency is a possible contributor, not a confirmed explanation for the launcher exception. Reloading the solution is required to refresh SSDT's in-memory model after external project changes.

A direct SSIS 2025 runtime probe could not initialize Runtime.Application because its COM runtime is not installed for execution outside Visual Studio. Verify-SqlTasks -Ssis2025 is available for installations with that runtime. The user must confirm both debugger launch and adapter behavior in SSDT; older-runtime LocalDB success alone does not establish this.

## Confirmed metadata failure: missing sys.columns.is_hidden

The user supplied the complete inner error: Invalid column name 'is_hidden'. The generic IDataAdapter wording wrapped this SQL compilation error; a provider incompatibility was not established. The previous diagnosis based on the truncated message was incorrect.

The metadata predicate now uses ISNULL(COLUMNPROPERTY(c.object_id,c.name,'IsHidden'),0)=0, so it does not reference the newer catalog column directly. Existing support for hidden-column exclusion is retained where the property is available, while NULL falls back to ordinary columns on catalogs without that property.

Both packages rebuilt successfully. Verify-SqlTasks -LegacyMetadataCatalog -KeyTypes passed with isolated fixture 20261021_083513: its SQL projects sys.columns without is_hidden and requests an unavailable COLUMNPROPERTY property to exercise NULL fallback. All 3508 eligible records exported and their keys deleted correctly, with 3 retained noneligible source rows. The test uses the local SQL engine to simulate catalog/property absence; no claim is made that an older remote server was accessed. This regression scenario is included in Verify-DailyArchive.

Reference: https://learn.microsoft.com/en-us/sql/t-sql/functions/columnproperty-transact-sql

## Simplified metadata discovery

Removed the custom catalog query (index selection, joins to sys.columns/sys.types, and type reconstruction CASE expressions). BeginScript now prepares a short SELECT of ColumnName, SqlType and IsKey from sys.dm_exec_describe_first_result_set with browse information enabled. SQL Server supplies the types and key information; Execute SQL Task still executes the query. Process table metadata derives the existing short header type from the returned type definition and retains rowversion conversion handling.

Both packages rebuilt; static checks confirm the large catalog query is absent from embedded scripts. Verify-SqlTasks -KeyTypes passed on isolated fixture 20261021_084209: 3508 exported rows, exact order keys, composite key types, correct deletion and 3 retained source rows. This uses the local SQL engine, not a full SSDT scheduler run. The previous LegacyMetadataCatalog simulation flag is retired because the query no longer accesses sys.columns at all.

Documentation: https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-objects/sys-dm-exec-describe-first-result-set-transact-sql
