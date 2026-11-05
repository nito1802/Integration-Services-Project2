USE master;
GO
IF DB_ID(N'SsisArchiveTest') IS NULL CREATE DATABASE SsisArchiveTest;
GO
USE SsisArchiveTest;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF SCHEMA_ID(N'Archive') IS NULL EXEC(N'CREATE SCHEMA Archive');
IF SCHEMA_ID(N'Demo') IS NULL EXEC(N'CREATE SCHEMA Demo');
IF OBJECT_ID(N'Archive.ArchiveJobs',N'U') IS NULL
CREATE TABLE Archive.ArchiveJobs (
 Id int IDENTITY PRIMARY KEY, DatabaseName nvarchar(128) NOT NULL,
 TableName nvarchar(257) NOT NULL, DateColumn nvarchar(128) NOT NULL,
 ArchiveOlderThanDays int NOT NULL, LastSuccesProcessedAt datetime2(7) NULL,
 LastProcessedAt datetime2(7) NULL, LastProcessedStatus nvarchar(16) NULL,
 ErrorMessage nvarchar(max) NULL
);
-- Seed each table only when first created. Restarting preserves archive results.
DECLARE @Today datetime2(7)=CONVERT(date,GETDATE());
IF OBJECT_ID(N'Demo.Orders',N'U') IS NULL
BEGIN
 CREATE TABLE Demo.Orders(Id int IDENTITY PRIMARY KEY,CreatedAt datetime2(7) NOT NULL,
  Amount decimal(19,4) NOT NULL,Note nvarchar(200) NULL);
 ;WITH N AS (SELECT TOP(7500) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
 INSERT Demo.Orders(CreatedAt,Amount,Note)
 SELECT DATEADD(second,CONVERT(int,n%2500),DATEADD(day,-40-CONVERT(int,(n-1)/2500),@Today)),
 n*1.2345,CASE WHEN n%7=0 THEN NULL ELSE N'Zażółć; "cytat"'+NCHAR(13)+NCHAR(10)+N'druga linia' END FROM N;
 INSERT Demo.Orders(CreatedAt,Amount,Note) VALUES(@Today,10,N'recent - keep'),(DATEADD(day,-30,@Today),20,N'cutoff - keep');
 INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
 VALUES(DB_NAME(),N'Demo.Orders',N'CreatedAt',30);
END;
IF OBJECT_ID(N'Demo.Events',N'U') IS NULL
BEGIN
 CREATE TABLE Demo.Events(Kind nvarchar(20) NOT NULL,SequenceNo int NOT NULL,
 HappenedAt datetime2(7) NOT NULL,Details nvarchar(200) NULL,CONSTRAINT PK_DemoEvents PRIMARY KEY(Kind,SequenceNo));
 ;WITH N AS (SELECT TOP(2002) ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
 INSERT Demo.Events SELECT N'Sensor',CONVERT(int,n),DATEADD(day,CASE WHEN n<=1001 THEN -60 ELSE -35 END,@Today),N'event' FROM N;
 INSERT Demo.Events VALUES(N'Sensor',3000,@Today,N'recent - keep');
 INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
 VALUES(DB_NAME(),N'Demo.Events',N'HappenedAt',30);
END;
IF OBJECT_ID(N'Demo.EmptyTable',N'U') IS NULL
BEGIN
 CREATE TABLE Demo.EmptyTable(Id int PRIMARY KEY,CreatedAt datetime2(7) NOT NULL);
 INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
 VALUES(DB_NAME(),N'Demo.EmptyTable',N'CreatedAt',30);
END;
COMMIT;
SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) Version,CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) Edition;
SELECT N'Demo.Orders' TableName,COUNT(*) RowsCount FROM Demo.Orders
UNION ALL SELECT N'Demo.Events',COUNT(*) FROM Demo.Events
UNION ALL SELECT N'Demo.EmptyTable',COUNT(*) FROM Demo.EmptyTable;
SELECT * FROM Archive.ArchiveJobs ORDER BY Id;
