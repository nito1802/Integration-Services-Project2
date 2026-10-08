param([switch]$IncludeFailure)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$run=Join-Path $root ('verification\'+[datetime]::Now.ToString('yyyyMMdd_HHmmss'))
[void](New-Item -ItemType Directory -Path $run -Force)
$name='CodexArchiveFlow_'+[Guid]::NewGuid().ToString('N')
$connection=New-Object Data.SqlClient.SqlConnection('Data Source=(localdb)\MSSQLLocalDB;Integrated Security=True;Initial Catalog=master;Connect Timeout=60')
try {
 $connection.Open(); $command=$connection.CreateCommand(); $command.CommandTimeout=60
 $dataPath=(Join-Path $run 'test.mdf').Replace("'","''"); $logPath=(Join-Path $run 'test_log.ldf').Replace("'","''")
 $command.CommandText="CREATE DATABASE [$name] ON PRIMARY (NAME=N'ArchiveTest',FILENAME=N'$dataPath') LOG ON (NAME=N'ArchiveTestLog',FILENAME=N'$logPath');"
 [void]$command.ExecuteNonQuery(); $connection.ChangeDatabase($name)
 $command.CommandText=@'
EXEC(N'CREATE SCHEMA audit');
EXEC(N'CREATE SCHEMA Archive');
'@
 [void]$command.ExecuteNonQuery()
 $command.CommandText=@'
CREATE TABLE dbo.Orders (OrderNo bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,CreatedAt datetime2 NOT NULL,Note nvarchar(200) NULL,Amount decimal(19,4) NOT NULL);
CREATE TABLE audit.Events (Kind nvarchar(30) NOT NULL,SequenceNo int NOT NULL,HappenedAt datetime2 NOT NULL,Details nvarchar(200) NULL,CONSTRAINT PK_Events PRIMARY KEY(Kind,SequenceNo));
CREATE TABLE dbo.EmptyTable (Code int PRIMARY KEY,CreatedAt datetime2 NOT NULL);
CREATE TABLE Archive.ArchiveJobs(Id int IDENTITY PRIMARY KEY,DatabaseName nvarchar(128) NOT NULL,TableName nvarchar(257) NOT NULL,DateColumn nvarchar(128) NOT NULL,ArchiveOlderThanDays int NOT NULL,LastSuccesProcessedAt datetime2 NULL,LastProcessedAt datetime2 NULL,LastProcessedStatus nvarchar(16) NULL,ErrorMessage nvarchar(max) NULL);
CREATE TABLE Archive.ProcessingAudit(AuditId int IDENTITY PRIMARY KEY,JobId int,Status nvarchar(16) NULL,ErrorMessage nvarchar(max) NULL,LastProcessedAt datetime2 NULL,LastSuccesProcessedAt datetime2 NULL);
DECLARE @Today date=CONVERT(date,GETDATE());
SET IDENTITY_INSERT dbo.Orders ON;
WITH N AS (SELECT TOP(2505) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.Orders(OrderNo,CreatedAt,Note,Amount) SELECT n,DATEADD(day,-3,@Today),CASE WHEN n%7=0 THEN NULL ELSE N'semi; "quote"'+CHAR(13)+CHAR(10)+N'Zażółć gęślą jaźń' END,n*1.2345 FROM N;
INSERT dbo.Orders(OrderNo,CreatedAt,Note,Amount) VALUES(3000,DATEADD(day,-2,@Today),N'last eligible day',7),(3001,DATEADD(day,-1,@Today),N'at excluded cutoff',8),(3002,@Today,N'today excluded',9);
SET IDENTITY_INSERT dbo.Orders OFF;
WITH N AS (SELECT TOP(1001) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT audit.Events SELECT CASE WHEN n%2=0 THEN N'A' ELSE N'B' END,n,DATEADD(day,-4,@Today),N'event; "quoted"' FROM N;
INSERT audit.Events VALUES(N'A',2000,DATEADD(day,-2,@Today),NULL),(N'C',2000,DATEADD(day,-1,@Today),N'at cutoff');
SET IDENTITY_INSERT Archive.ArchiveJobs ON;
INSERT Archive.ArchiveJobs(Id,DatabaseName,TableName,DateColumn,ArchiveOlderThanDays,LastSuccesProcessedAt,ErrorMessage) VALUES
(1,DB_NAME(),N'dbo.Orders',N'CreatedAt',1,'2025-01-01',N'old failure'),
(3,DB_NAME(),N'audit.Events',N'HappenedAt',1,'2025-01-01',N'old failure'),
(4,DB_NAME(),N'dbo.EmptyTable',N'CreatedAt',1,'2025-01-01',N'old failure');
SET IDENTITY_INSERT Archive.ArchiveJobs OFF;
'@
 $archive=Join-Path $run 'csv'
 [void]$command.Parameters.Add('@Root',[Data.SqlDbType]::NVarChar,2048); $command.Parameters['@Root'].Value=$archive
 [void]$command.ExecuteNonQuery()
 $command.Parameters.Clear()
 $command.CommandText='CREATE TRIGGER Archive.RecordProcessingAudit ON Archive.ArchiveJobs AFTER UPDATE AS INSERT Archive.ProcessingAudit(JobId,Status,ErrorMessage,LastProcessedAt,LastSuccesProcessedAt) SELECT Id,LastProcessedStatus,ErrorMessage,LastProcessedAt,LastSuccesProcessedAt FROM inserted;'
 [void]$command.ExecuteNonQuery()
 if($IncludeFailure) {
  $command.CommandText="SET IDENTITY_INSERT Archive.ArchiveJobs ON; INSERT Archive.ArchiveJobs(Id,DatabaseName,TableName,DateColumn,ArchiveOlderThanDays,LastSuccesProcessedAt,ErrorMessage) VALUES(2,DB_NAME(),N'dbo.Orders',N'MissingDateColumn',1,'2025-01-01',N'old failure'); SET IDENTITY_INSERT Archive.ArchiveJobs OFF;"
  [void]$command.ExecuteNonQuery()
 }
 $config=[ordered]@{Database=$name;ConnectionString="Data Source=(localdb)\MSSQLLocalDB;Integrated Security=True;Initial Catalog=$name;Connect Timeout=60";ArchiveRoot=$archive;RunDirectory=$run}
 $configPath=Join-Path $run 'config.json'; $config|ConvertTo-Json|Set-Content -LiteralPath $configPath -Encoding UTF8
 Set-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt') -Value $configPath
 Write-Output ('Test database: '+$name)
 Write-Output ('Config: '+$configPath)
}finally{$connection.Dispose()}
