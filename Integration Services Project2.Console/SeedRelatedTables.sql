-- Run with the archive package stopped.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() <> N'nito_superDb' THROW 50002, 'Expected nito_superDb.', 1;

BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @LockResult int;
    EXEC @LockResult = sys.sp_getapplock @Resource=N'ArchiveRelationTest.Seed',
        @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=10000;
    IF @LockResult < 0 THROW 50003, 'Could not acquire relation seed lock.', 1;

    IF SCHEMA_ID(N'ArchiveRelationTest') IS NULL EXEC(N'CREATE SCHEMA ArchiveRelationTest');

    IF OBJECT_ID(N'ArchiveRelationTest.Orders', N'U') IS NULL
        CREATE TABLE ArchiveRelationTest.Orders (
            Id int NOT NULL CONSTRAINT PK_ArchiveRelationTest_Orders PRIMARY KEY,
            CreatedAt datetime2(7) NOT NULL
        );
    IF OBJECT_ID(N'ArchiveRelationTest.OrderLines', N'U') IS NULL
    BEGIN
        CREATE TABLE ArchiveRelationTest.OrderLines (
            Id int NOT NULL CONSTRAINT PK_ArchiveRelationTest_OrderLines PRIMARY KEY,
            OrderId int NOT NULL,
            Payload nvarchar(100) NOT NULL,
            CONSTRAINT FK_ArchiveRelationTest_OrderLines_Orders FOREIGN KEY (OrderId)
                REFERENCES ArchiveRelationTest.Orders(Id)
        );
        CREATE INDEX IX_ArchiveRelationTest_OrderLines_OrderId ON ArchiveRelationTest.OrderLines(OrderId);
    END;

    DELETE FROM ArchiveRelationTest.OrderLines;
    DELETE FROM ArchiveRelationTest.Orders;

    DECLARE @Today date=CONVERT(date, SYSDATETIME());
    INSERT ArchiveRelationTest.Orders (Id, CreatedAt)
    VALUES (1, DATEADD(day,-60,@Today)), (2, DATEADD(day,-59,@Today)), (3, @Today);
    INSERT ArchiveRelationTest.OrderLines (Id, OrderId, Payload)
    VALUES (101,1,N'Old order, first line'), (102,1,N'Old order, second line'),
           (103,2,N'Another old order'), (104,3,N'Current order');

    DECLARE @JobId int;
    SELECT @JobId=Id FROM Archive.ArchiveJobs
    WHERE DatabaseName=DB_NAME() AND TableName=N'ArchiveRelationTest.Orders';
    IF @@ROWCOUNT > 1 THROW 50004, 'Duplicate archive jobs for ArchiveRelationTest.Orders.', 1;

    IF @JobId IS NULL
    BEGIN
        INSERT Archive.ArchiveJobs (DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
        VALUES (DB_NAME(),N'ArchiveRelationTest.Orders',N'CreatedAt',30);
        SET @JobId=CONVERT(int,SCOPE_IDENTITY());
    END
    ELSE
        UPDATE Archive.ArchiveJobs SET DateColumn=N'CreatedAt', ArchiveOlderThanDays=30,
            LastSuccesProcessedAt=NULL, LastProcessedAt=NULL, LastProcessedStatus=NULL, ErrorMessage=NULL
        WHERE Id=@JobId;

    DELETE FROM Archive.ArchiveJobRelations WHERE ArchiveJobId=@JobId
        AND ChildSchema=N'ArchiveRelationTest' AND ChildTable=N'OrderLines';
    INSERT Archive.ArchiveJobRelations (ArchiveJobId,ChildSchema,ChildTable,ParentKeyColumn,ChildKeyColumn)
    VALUES (@JobId,N'ArchiveRelationTest',N'OrderLines',N'Id',N'OrderId');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
