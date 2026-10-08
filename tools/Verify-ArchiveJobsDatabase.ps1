param([switch]$BeforeMigration)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2.Database\appsettings.Local.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$connection=New-Object Data.SqlClient.SqlConnection($config.ConnectionStrings.ArchiveJobsDatabase)
try {
    $connection.Open()
    $command=$connection.CreateCommand()
    if($BeforeMigration) {
        $command.CommandText="SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name=N'Archive' AND t.name IN(N'ArchiveJobs',N'__EFMigrationsHistory');"
        if([int]$command.ExecuteScalar() -ne 0) { throw 'ArchiveJobs objects already exist. Inspect before applying the initial migration.' }
        'Verified: no conflicting ArchiveJobs table or migration history in the Archive schema.'
        return
    }
    $command.CommandText=@'
SELECT c.name,TYPE_NAME(c.system_type_id) AS SqlType,c.is_nullable,c.is_identity
FROM sys.columns c WHERE c.object_id=OBJECT_ID(N'Archive.ArchiveJobs') ORDER BY c.column_id;
'@
    $adapter=New-Object Data.SqlClient.SqlDataAdapter($command)
    $columns=New-Object Data.DataTable
    [void]$adapter.Fill($columns)
    $expected=@{Id='int';DatabaseName='nvarchar';TableName='nvarchar';LastSuccesProcessedAt='date';ArchiveOlderThanDays='int'}
    if($columns.Rows.Count -ne 5) { throw 'Expected exactly five table columns' }
    foreach($column in $columns.Rows) {
        if($expected[$column.name] -ne $column.SqlType -or $column.is_nullable) { throw ('Unexpected column definition: '+$column.name) }
        if($column.name -eq 'Id' -and !$column.is_identity) { throw 'Id must be an identity column' }
    }
    $command.CommandText='SELECT COUNT(*) FROM Archive.ArchiveJobs;'
    if([int]$command.ExecuteScalar() -ne 8) { throw 'Expected eight sample rows' }
    $command.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobs WHERE DatabaseName=N'' OR TableName=N'' OR ArchiveOlderThanDays<=0;"
    if([int]$command.ExecuteScalar() -ne 0) { throw 'Invalid sample data' }
    $command.CommandText='SELECT COUNT(*) FROM Archive.__EFMigrationsHistory;'
    if([int]$command.ExecuteScalar() -ne 1) { throw 'Expected one applied migration' }
    $command.CommandText='SELECT Id,DatabaseName,TableName,LastSuccesProcessedAt,ArchiveOlderThanDays FROM Archive.ArchiveJobs ORDER BY Id;'
    $rows=New-Object Data.DataTable
    [void]$adapter.Fill($rows)
    $rows | Format-Table -AutoSize
    'PASS: Archive.ArchiveJobs; five columns; int identity key; SQL date; eight sample rows; isolated migration history.'
} finally { $connection.Dispose() }
