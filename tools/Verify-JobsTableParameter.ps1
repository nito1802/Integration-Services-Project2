$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Create-TestDatabase.ps1') -IncludeFailure
if($LASTEXITCODE -ne 0) { throw 'Fixture creation failed' }
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB' }
$ddl=Get-Content -LiteralPath (Join-Path $root 'CreateArchiveJobs.sql') -Raw
$ddl=$ddl.Replace("@SchemaName sysname=N'Archive'","@SchemaName sysname=N'dbo'").Replace("@TableName sysname=N'ArchiveJobs'","@TableName sysname=N'Archive jobs'")
$db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
try {
    $cmd=$db.CreateCommand(); $cmd.CommandText=$ddl; [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText=@'
SET IDENTITY_INSERT dbo.[Archive jobs] ON;
INSERT dbo.[Archive jobs] (Id,DatabaseName,TableName,LastSuccesProcessedAt,DateColumn,LastProcessedAt,LastProcessedStatus,ErrorMessage,ArchiveOlderThanDays)
SELECT Id,DatabaseName,TableName,LastSuccesProcessedAt,DateColumn,LastProcessedAt,LastProcessedStatus,ErrorMessage,ArchiveOlderThanDays FROM Archive.ArchiveJobs;
SET IDENTITY_INSERT dbo.[Archive jobs] OFF;
DROP TABLE Archive.ArchiveJobs;
'@
    [void]$cmd.ExecuteNonQuery()
    # Re-running the creation script must retain all four existing job rows.
    $cmd.CommandText=$ddl; [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText='SELECT COUNT(*) FROM dbo.[Archive jobs];'
    if($cmd.ExecuteScalar() -ne 4) { throw 'Creation script changed existing jobs' }
    $missing='NoSchema_'+[Guid]::NewGuid().ToString('N')
    $cmd.CommandText=$ddl.Replace("@SchemaName sysname=N'dbo'","@SchemaName sysname=N'$missing'")
    $rejected=$false
    try { [void]$cmd.ExecuteNonQuery() } catch { if($_.Exception.ToString() -notlike '*configured schema does not exist*') { throw }; $rejected=$true }
    if(!$rejected) { throw 'Missing schema was not rejected' }
    $cmd.CommandText="SELECT SCHEMA_ID(N'$missing');"
    if($cmd.ExecuteScalar() -ne [DBNull]::Value) { throw 'Creation script created a schema' }
} finally { $db.Dispose() }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SqlTasks.ps1') -JobsTable 'dbo.Archive jobs' -FailureMode Read
if($LASTEXITCODE -ne 0) { throw 'Custom jobs table failure/continuation test failed' }
Write-Output 'PASS: custom dbo.Archive jobs table, spaces, configurable statuses, existing-row preservation, no schema creation'
