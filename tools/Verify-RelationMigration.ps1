$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Create-TestDatabase.ps1') -IncludeFailure
if($LASTEXITCODE -ne 0) { throw 'Fixture creation failed' }
$config=Get-Content (Get-Content (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated fixture' }
$connection=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
try {
    $connection.Open()
    $cmd=$connection.CreateCommand()
    $migration=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
    # Fresh creation must be independent of ArchiveJobs.
    $cmd.CommandText='EXEC sys.sp_rename N''Archive.ArchiveJobs'',N''Jobs temporarily renamed'',''OBJECT'';'
    [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText=$migration; [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText='DROP TABLE Archive.ArchiveJobRelations; EXEC sys.sp_rename N''Archive.Jobs temporarily renamed'',N''ArchiveJobs'',''OBJECT'';'
    [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText=@'
CREATE TABLE Archive.ArchiveJobRelations(
    Id int IDENTITY CONSTRAINT PK_ArchiveJobRelations PRIMARY KEY,
    ArchiveJobId int NOT NULL REFERENCES Archive.ArchiveJobs(Id),
    DatabaseName nvarchar(128) NOT NULL,
    ParentTable nvarchar(257) NOT NULL DEFAULT N'',
    ChildTable nvarchar(257) NOT NULL,
    ParentKeyColumn sysname NOT NULL,
    ChildKeyColumn sysname NOT NULL
);
INSERT Archive.ArchiveJobRelations(ArchiveJobId,DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
VALUES(1,DB_NAME(),N'',N'dbo.Lines',N'OrderNo',N'OrderId'),
      (2,DB_NAME(),N'dbo.Orders',N'dbo.Lines',N'OrderNo',N'OrderId'),
      (2,DB_NAME(),N'dbo.Lines',N'dbo.Details',N'Id',N'LineId');
'@
    [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText=$migration
    [void]$cmd.ExecuteNonQuery()
    [void]$cmd.ExecuteNonQuery()
    $cmd.CommandText="SELECT COL_LENGTH(N'Archive.ArchiveJobRelations',N'ArchiveJobId');"
    if($cmd.ExecuteScalar() -ne [DBNull]::Value) { throw 'ArchiveJobId still exists' }
    $cmd.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobRelations WHERE Id IN(1,3) AND ParentTable IN(N'dbo.Orders',N'dbo.Lines');"
    if($cmd.ExecuteScalar() -ne 2) { throw 'Migration failed to preserve/normalize/deduplicate edges' }
    $cmd.CommandText='DELETE FROM Archive.ArchiveJobs WHERE Id IN(1,2); SELECT COUNT(*) FROM Archive.ArchiveJobRelations;'
    if($cmd.ExecuteScalar() -ne 2) { throw 'Relations depend on a job lifecycle' }
    $cmd.CommandText="INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn) VALUES(DB_NAME(),N'dbo.Orders',N'dbo.Lines',N'OrderNo',N'OrderId');"
    $rejected=$false
    try { [void]$cmd.ExecuteNonQuery() } catch {
        if($_.Exception.ToString() -notlike '*duplicate*') { throw }
        $rejected=$true
    }
    if(!$rejected) { throw 'Duplicate relation was accepted' }
    $other=$config.Database+'_Other'
    $dataPath=(Join-Path $config.RunDirectory 'seed-other.mdf').Replace("'","''")
    $logPath=(Join-Path $config.RunDirectory 'seed-other.ldf').Replace("'","''")
    $cmd.CommandText="CREATE DATABASE [$other] ON PRIMARY (NAME=N'OtherData',FILENAME=N'$dataPath') LOG ON (NAME=N'OtherLog',FILENAME=N'$logPath');"
    [void]$cmd.ExecuteNonQuery()
    $seed=(Get-Content (Join-Path $root 'Integration Services Project2.Console/SeedAll.sql') -Raw).
        Replace('nito_superDb',$config.Database).Replace('nito_SomeApps',$other)
    [void]$cmd.Parameters.Add('@DatabaseName',[Data.SqlDbType]::NVarChar,128)
    $firstIds=$null
    foreach($round in 1..2) {
        $transaction=$connection.BeginTransaction()
        $cmd.Transaction=$transaction
        try {
            $cmd.CommandText=$seed
            foreach($source in @($config.Database,$other)) {
                $cmd.Parameters['@DatabaseName'].Value=$source
                [void]$cmd.ExecuteNonQuery()
            }
            $transaction.Commit()
        } catch { $transaction.Rollback(); throw }
        $cmd.Transaction=$null
        $cmd.CommandText="SELECT CHECKSUM_AGG(CHECKSUM(Id,DatabaseName,TableName)) FROM Archive.ArchiveJobs WHERE TableName LIKE N'ArchiveScenarioTest.%';"
        $ids=$cmd.ExecuteScalar()
        if($round -eq 1) { $firstIds=$ids }
        elseif($firstIds -ne $ids) { throw 'Seed changed job identities' }
        $cmd.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobRelations WHERE ParentTable LIKE N'ArchiveScenarioTest.%';"
        if($cmd.ExecuteScalar() -ne 50) { throw 'Seed did not preserve exactly 50 shared edges' }
        foreach($source in @($config.Database,$other)) {
            $cmd.CommandText="SELECT SUM(p.rows) FROM [$source].sys.tables t JOIN [$source].sys.schemas s ON s.schema_id=t.schema_id JOIN [$source].sys.partitions p ON p.object_id=t.object_id AND p.index_id IN(0,1) WHERE s.name=N'ArchiveScenarioTest';"
            if($cmd.ExecuteScalar() -ne 189) { throw "Unexpected seeded data count in $source" }
        }
    }
    Write-Output 'PASS: independent creation; migration/deduplication; job removal preserves relations; repeated migration and two-database seed are safe; stable job Ids; 50 shared edges and 189 rows per database.'
} finally { $connection.Dispose() }
