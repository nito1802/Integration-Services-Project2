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
CREATE SCHEMA audit;
'@
 [void]$command.ExecuteNonQuery()
 $command.CommandText=@'
CREATE TABLE dbo.Orders (OrderNo bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,CreatedAt datetime2 NOT NULL,Note nvarchar(200) NULL,Amount decimal(19,4) NOT NULL);
CREATE TABLE audit.Events (Kind nvarchar(30) NOT NULL,SequenceNo int NOT NULL,HappenedAt datetime2 NOT NULL,Details nvarchar(200) NULL,CONSTRAINT PK_Events PRIMARY KEY(Kind,SequenceNo));
CREATE TABLE dbo.EmptyTable (Code int PRIMARY KEY,CreatedAt datetime2 NOT NULL);
CREATE TABLE dbo.CasherSettings(Id int PRIMARY KEY,DictionaryType nvarchar(50),TableName nvarchar(256),Days int,ColumnDate nvarchar(128),ArchiwumPath nvarchar(2048));
DECLARE @Today date=CONVERT(date,GETDATE());
SET IDENTITY_INSERT dbo.Orders ON;
WITH N AS (SELECT TOP(2505) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.Orders(OrderNo,CreatedAt,Note,Amount) SELECT n,DATEADD(day,-3,@Today),CASE WHEN n%7=0 THEN NULL ELSE N'semi; "quote"'+CHAR(13)+CHAR(10)+N'Zażółć gęślą jaźń' END,n*1.2345 FROM N;
INSERT dbo.Orders(OrderNo,CreatedAt,Note,Amount) VALUES(3000,DATEADD(day,-2,@Today),N'last eligible day',7),(3001,DATEADD(day,-1,@Today),N'at excluded cutoff',8),(3002,@Today,N'today excluded',9);
SET IDENTITY_INSERT dbo.Orders OFF;
WITH N AS (SELECT TOP(1001) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT audit.Events SELECT CASE WHEN n%2=0 THEN N'A' ELSE N'B' END,n,DATEADD(day,-4,@Today),N'event; "quoted"' FROM N;
INSERT audit.Events VALUES(N'A',2000,DATEADD(day,-2,@Today),NULL),(N'C',2000,DATEADD(day,-1,@Today),N'at cutoff');
INSERT dbo.CasherSettings VALUES(1,N'Archiwum',N'dbo.Orders',1,N'CreatedAt',@Root),(2,N'Archiwum',N'audit.Events',1,N'HappenedAt',@Root),(3,N'Archiwum',N'dbo.EmptyTable',1,N'CreatedAt',@Root);
'@
 $archive=Join-Path $run 'csv'
 [void]$command.Parameters.Add('@Root',[Data.SqlDbType]::NVarChar,2048); $command.Parameters['@Root'].Value=$archive
 [void]$command.ExecuteNonQuery()
 $config=[ordered]@{Database=$name;ConnectionString="Data Source=(localdb)\MSSQLLocalDB;Integrated Security=True;Initial Catalog=$name;Connect Timeout=60";ArchiveRoot=$archive;RunDirectory=$run}
 $configPath=Join-Path $run 'config.json'; $config|ConvertTo-Json|Set-Content -LiteralPath $configPath -Encoding UTF8
 Set-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt') -Value $configPath
 Write-Output ('Test database: '+$name)
 Write-Output ('Config: '+$configPath)
}finally{$connection.Dispose()}
