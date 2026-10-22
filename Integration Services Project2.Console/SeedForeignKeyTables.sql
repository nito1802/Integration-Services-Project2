-- Recreates only the dedicated ArchiveFkTest data and its four archive jobs.
-- Run while the archive package is stopped. All changes form one transaction.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'nito_superDb' THROW 50001, 'Expected nito_superDb.', 1;
IF OBJECT_ID(N'Archive.ArchiveJobs', N'U') IS NULL
    THROW 50002, 'Archive.ArchiveJobs must exist.', 1;
BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @LockResult int;
    EXEC @LockResult = sys.sp_getapplock @Resource=N'ArchiveFkTest.Seed',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=10000;
    IF @LockResult < 0 THROW 50003, 'Could not acquire FK seed lock.', 1;
    IF SCHEMA_ID(N'ArchiveFkTest') IS NULL EXEC(N'CREATE SCHEMA ArchiveFkTest');

    IF OBJECT_ID(N'ArchiveFkTest.GoodParent', N'U') IS NULL
        CREATE TABLE ArchiveFkTest.GoodParent (
            Id int NOT NULL CONSTRAINT PK_ArchiveFkTest_GoodParent PRIMARY KEY,
            CreatedAt datetime2(7) NOT NULL,
            Payload nvarchar(100) NOT NULL
        );
    IF OBJECT_ID(N'ArchiveFkTest.GoodChild', N'U') IS NULL
        CREATE TABLE ArchiveFkTest.GoodChild (
            Id int NOT NULL CONSTRAINT PK_ArchiveFkTest_GoodChild PRIMARY KEY,
            ParentId int NOT NULL,
            CreatedAt datetime2(7) NOT NULL,
            Payload nvarchar(100) NOT NULL,
            CONSTRAINT FK_ArchiveFkTest_GoodChild_GoodParent FOREIGN KEY (ParentId)
                REFERENCES ArchiveFkTest.GoodParent(Id) ON DELETE NO ACTION
        );
    IF OBJECT_ID(N'ArchiveFkTest.BadParent', N'U') IS NULL
        CREATE TABLE ArchiveFkTest.BadParent (
            Id int NOT NULL CONSTRAINT PK_ArchiveFkTest_BadParent PRIMARY KEY,
            CreatedAt datetime2(7) NOT NULL,
            Payload nvarchar(100) NOT NULL
        );
    IF OBJECT_ID(N'ArchiveFkTest.BadChild', N'U') IS NULL
        CREATE TABLE ArchiveFkTest.BadChild (
            Id int NOT NULL CONSTRAINT PK_ArchiveFkTest_BadChild PRIMARY KEY,
            ParentId int NOT NULL,
            CreatedAt datetime2(7) NOT NULL,
            Payload nvarchar(100) NOT NULL,
            CONSTRAINT FK_ArchiveFkTest_BadChild_BadParent FOREIGN KEY (ParentId)
                REFERENCES ArchiveFkTest.BadParent(Id) ON DELETE NO ACTION
        );

    DELETE FROM ArchiveFkTest.GoodChild;
    DELETE FROM ArchiveFkTest.GoodParent;
    DELETE FROM ArchiveFkTest.BadChild;
    DELETE FROM ArchiveFkTest.BadParent;
    DECLARE @Rows TABLE (Id int NOT NULL PRIMARY KEY, CreatedAt datetime2(7) NOT NULL);
    ;WITH Digits AS (
        SELECT n FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(n)
    )
    INSERT @Rows (Id, CreatedAt)
    SELECT 1+a.n+10*b.n+100*c.n,
        DATEADD(second, ((a.n+10*b.n+100*c.n)%100)*600,
            DATEADD(day, (a.n+10*b.n+100*c.n)/100, CONVERT(datetime2(7),'20250101')))
    FROM Digits a CROSS JOIN Digits b CROSS JOIN Digits c;
    INSERT ArchiveFkTest.GoodParent SELECT Id,CreatedAt,CONCAT(N'Good parent ',Id) FROM @Rows;
    INSERT ArchiveFkTest.GoodChild SELECT Id,Id,CreatedAt,CONCAT(N'Good child ',Id) FROM @Rows;
    INSERT ArchiveFkTest.BadParent SELECT Id,CreatedAt,CONCAT(N'Bad parent ',Id) FROM @Rows;
    INSERT ArchiveFkTest.BadChild SELECT Id,Id,CreatedAt,CONCAT(N'Bad child ',Id) FROM @Rows;

    -- Assign fresh identity values in explicit order. Other jobs remain untouched.
    DELETE FROM Archive.ArchiveJobs WHERE DatabaseName=N'nito_superDb'
        AND TableName IN (N'ArchiveFkTest.GoodChild',N'ArchiveFkTest.GoodParent',
                          N'ArchiveFkTest.BadParent',N'ArchiveFkTest.BadChild');
    DECLARE @Jobs TABLE (Id int NOT NULL, TableName nvarchar(257) NOT NULL);
    INSERT Archive.ArchiveJobs (DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
        OUTPUT inserted.Id,inserted.TableName INTO @Jobs
        VALUES (N'nito_superDb',N'ArchiveFkTest.GoodChild',N'CreatedAt',30);
    INSERT Archive.ArchiveJobs (DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
        OUTPUT inserted.Id,inserted.TableName INTO @Jobs
        VALUES (N'nito_superDb',N'ArchiveFkTest.GoodParent',N'CreatedAt',30);
    INSERT Archive.ArchiveJobs (DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
        OUTPUT inserted.Id,inserted.TableName INTO @Jobs
        VALUES (N'nito_superDb',N'ArchiveFkTest.BadParent',N'CreatedAt',30);
    INSERT Archive.ArchiveJobs (DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
        OUTPUT inserted.Id,inserted.TableName INTO @Jobs
        VALUES (N'nito_superDb',N'ArchiveFkTest.BadChild',N'CreatedAt',30);
    COMMIT TRANSACTION;
    SELECT j.Id,j.TableName,1000 AS [RowCount],MIN(r.CreatedAt) AS FirstDate,
        MAX(r.CreatedAt) AS LastDate,COUNT(DISTINCT CONVERT(date,r.CreatedAt)) AS Days
    FROM @Jobs j CROSS JOIN @Rows r GROUP BY j.Id,j.TableName ORDER BY j.Id;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
