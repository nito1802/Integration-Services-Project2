param([switch]$Little)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content (Join-Path $root 'Integration Services Project2.Database/appsettings.json') -Raw | ConvertFrom-Json
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder($config.ConnectionStrings.ArchiveJobsDatabase)
foreach($database in @('nito_superDb','nito_SomeApps')) {
    $builder['Initial Catalog']=$database
    $connection=New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
    try {
        $connection.Open()
        $command=$connection.CreateCommand(); $command.CommandTimeout=180
        $command.CommandText=@'
SET NOCOUNT ON;
IF EXISTS(SELECT 1 FROM sys.tables WHERE schema_id=SCHEMA_ID(N'ArchiveScenarioTest'))
    THROW 50001,'Old scenario tables remain.',1;
IF (SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID(N'GenericSignatureTest'))<>9
    THROW 50001,'Expected nine model tables.',1;
DECLARE @Expected int=0,@Days int=0,@Offset int=0,@Date date='20230101';
WHILE @Date<=CONVERT(date,GETDATE()) BEGIN
    DECLARE @Count int=CASE WHEN @Offset%23=7 THEN 0 WHEN @Offset%31=0 THEN 35 ELSE 1+@Offset*17%9 END;
    SET @Expected+=@Count;
    IF @Count>0 SET @Days+=1;
    SET @Offset+=1; SET @Date=DATEADD(day,1,@Date);
END;
IF @Little=1 BEGIN SET @Expected=25; SET @Days=6; END;
IF @Little=1 AND EXISTS(SELECT 1 FROM GenericSignatureTest.Processes
    WHERE CONVERT(date,CreationDate) NOT IN ('20230103','20230105','20230307','20230309','20230612','20230614'))
    THROW 50001,'Unexpected date in the small seed.',1;
IF (SELECT COUNT(*) FROM GenericSignatureTest.Processes)<>@Expected THROW 50001,'Incorrect process count.',1;
IF (SELECT COUNT(DISTINCT CONVERT(date,CreationDate)) FROM GenericSignatureTest.Processes)<>@Days THROW 50001,'Incorrect populated day count.',1;
IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE parent_object_id IN
    (SELECT object_id FROM sys.tables WHERE schema_id=SCHEMA_ID(N'GenericSignatureTest')) AND (is_disabled=1 OR is_not_trusted=1))
    THROW 50001,'Foreign keys are disabled or untrusted.',1;
IF (SELECT COUNT(*) FROM nito_superDb.Archive.ArchiveJobRelations WHERE DatabaseName=DB_NAME() AND LEFT(ParentTable,21)=N'GenericSignatureTest.')<>6
    THROW 50001,'Expected six archive relations.',1;
IF (SELECT COUNT(*) FROM nito_superDb.Archive.ArchiveJobs WHERE DatabaseName=DB_NAME() AND TableName=N'GenericSignatureTest.Processes')<>1
    THROW 50001,'Expected one archive job.',1;
IF EXISTS(SELECT 1 FROM nito_superDb.Archive.ArchiveJobs
    WHERE DatabaseName=DB_NAME() AND TableName=N'GenericSignatureTest.Processes'
      AND (DateColumn<>N'CreationDate' OR ArchiveOlderThanDays<>30
        OR LastProcessedAt IS NOT NULL OR LastSuccesProcessedAt IS NOT NULL
        OR LastProcessedStatus IS NOT NULL OR ErrorMessage IS NOT NULL))
    THROW 50001,'Archive job was not reset correctly.',1;
IF EXISTS(
    SELECT 1 FROM nito_superDb.Archive.ArchiveJobRelations r
    WHERE r.DatabaseName=DB_NAME() AND LEFT(r.ParentTable,21)=N'GenericSignatureTest.'
      AND NOT EXISTS(
        SELECT 1 FROM sys.foreign_key_columns fc
        WHERE fc.referenced_object_id=OBJECT_ID(r.ParentTable)
          AND fc.parent_object_id=OBJECT_ID(r.ChildTable)
          AND COL_NAME(fc.referenced_object_id,fc.referenced_column_id)=r.ParentKeyColumn
          AND COL_NAME(fc.parent_object_id,fc.parent_column_id)=r.ChildKeyColumn))
    THROW 50001,'Archive relation does not match a physical foreign key.',1;
IF EXISTS(SELECT 1 FROM nito_superDb.Archive.ArchiveJobs WHERE DatabaseName=DB_NAME() AND LEFT(TableName,20)=N'ArchiveScenarioTest.')
 OR EXISTS(SELECT 1 FROM nito_superDb.Archive.ArchiveJobRelations WHERE DatabaseName=DB_NAME()
     AND (LEFT(ParentTable,20)=N'ArchiveScenarioTest.' OR LEFT(ChildTable,20)=N'ArchiveScenarioTest.'))
    THROW 50001,'Old scenario configuration remains.',1;
SELECT t.name,SUM(p.rows) AS Rows FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN(0,1)
WHERE t.schema_id=SCHEMA_ID(N'GenericSignatureTest') GROUP BY t.name ORDER BY t.name;
SELECT COUNT(*) AS Processes,MIN(CreationDate) AS FirstDate,MAX(CreationDate) AS LastDate,
    COUNT(DISTINCT CONVERT(date,CreationDate)) AS PopulatedDays,
    (SELECT Id FROM nito_superDb.Archive.ArchiveJobs WHERE DatabaseName=DB_NAME()
       AND TableName=N'GenericSignatureTest.Processes') AS ArchiveJobId
FROM GenericSignatureTest.Processes;
SELECT TOP(1) Data FROM GenericSignatureTest.ProcessData;
'@
        [void]$command.Parameters.Add('@Little',[System.Data.SqlDbType]::Bit)
        $command.Parameters['@Little'].Value=[bool]$Little
        $adapter=New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $data=New-Object System.Data.DataSet
        [void]$adapter.Fill($data)
        Write-Output $database
        $data.Tables[0] | Format-Table -AutoSize | Out-String | Write-Output
        $data.Tables[1] | Format-Table -AutoSize | Out-String | Write-Output
        $null=$data.Tables[2].Rows[0].Data | ConvertFrom-Json
    } finally { $connection.Dispose() }
}
