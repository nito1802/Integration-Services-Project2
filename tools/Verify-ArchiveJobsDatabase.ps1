$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Join-Path $root 'Integration Services Project2.Database\appsettings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$connection=New-Object Data.SqlClient.SqlConnection($config.ConnectionStrings.ArchiveJobsDatabase)
try {
    $connection.Open()
    $command=$connection.CreateCommand()
    $command.CommandText="SELECT c.name,TYPE_NAME(c.system_type_id) AS SqlType,c.is_nullable,c.is_identity FROM sys.columns c WHERE c.object_id=OBJECT_ID(N'Archive.ArchiveJobs');"
    $adapter=New-Object Data.SqlClient.SqlDataAdapter($command)
    $columns=New-Object Data.DataTable
    [void]$adapter.Fill($columns)
    $expected=@{Id='int';DatabaseName='nvarchar';TableName='nvarchar';LastSuccesProcessedAt='datetime2';ArchiveOlderThanDays='int';DateColumn='nvarchar';LastProcessedAt='datetime2';LastProcessedStatus='nvarchar';ErrorMessage='nvarchar'}
    if($columns.Rows.Count -ne $expected.Count) { throw 'Unexpected column count' }
    foreach($column in $columns.Rows) {
        $nullable=$column.name -in @('LastSuccesProcessedAt','LastProcessedAt','LastProcessedStatus','ErrorMessage')
        if($expected[$column.name] -ne $column.SqlType -or [bool]$column.is_nullable -ne $nullable) { throw ('Unexpected column definition: '+$column.name) }
        if($column.name -eq 'Id' -and !$column.is_identity) { throw 'Id must be an identity column' }
    }
    $command.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobs WHERE LastProcessedStatus IS NOT NULL AND LastProcessedStatus NOT IN(N'Error',N'Success');"
    if([int]$command.ExecuteScalar() -ne 0) { throw 'Status must be a string enum value' }
    $command.CommandText='SELECT Id,DatabaseName,TableName,DateColumn,LastSuccesProcessedAt,LastProcessedAt,LastProcessedStatus,ArchiveOlderThanDays FROM Archive.ArchiveJobs ORDER BY Id;'
    $rows=New-Object Data.DataTable
    [void]$adapter.Fill($rows)
    $rows | Format-Table -AutoSize
    'PASS: nine columns; identity key; nullable datetime2 timestamps; string status enum.'
} finally { $connection.Dispose() }
