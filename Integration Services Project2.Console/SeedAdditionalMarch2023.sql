-- One-off append-only seed. Each execution adds a new batch of 3 processes
-- and one related row per process in each of the six dependent tables.
-- Does not run LittleSeedAsync, reset jobs, or modify/archive existing data.
USE [nito_SomeApps];
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BatchId uniqueidentifier=NEWID();
DECLARE @Marker nvarchar(100)=N'extra-20230307-'+CONVERT(nvarchar(36),@BatchId);
DECLARE @ProcessType nvarchar(30), @Status nvarchar(64);
SELECT TOP(1) @ProcessType=Id FROM GenericSignatureTest.ProcessTypes
ORDER BY CASE WHEN Id=N'CUSTOMER_ONBOARDING' THEN 0 ELSE 1 END,Id;
SELECT TOP(1) @Status=Id FROM GenericSignatureTest.EkdStatuses
ORDER BY CASE WHEN Id=N'CREATED' THEN 0 ELSE 1 END,Id;
IF @ProcessType IS NULL OR @Status IS NULL
    THROW 50001,'Missing ProcessTypes/EkdStatuses dictionaries. Run the initial seed first.',1;

DECLARE @New TABLE(ProcessId uniqueidentifier,EnvelopeId nvarchar(450),EkdId uniqueidentifier,CreatedAt datetime2(7),Number int);
INSERT @New
SELECT NEWID(),CONVERT(nvarchar(36),NEWID()),NEWID(),
    DATEADD(minute,(n-1)*5,CONVERT(datetime2(7),'2023-03-07T12:00:00')),n
FROM (VALUES(1),(2),(3)) v(n);

BEGIN TRY
    BEGIN TRANSACTION;
    INSERT GenericSignatureTest.Processes
        (Id,ProcessTypeId,SignatureTypeId,Ai2Key,EqNumber,Status,CreationDate,
         SignatureTypeSelectionDate,AvailableSignatureTypes,UserLogin,ClientWorkingMode,ExternalId)
    SELECT ProcessId,@ProcessType,N'AUTENTI',N'EXTRA20230307',N'EXTRA-'+CONVERT(nvarchar(10),Number),N'Success',CreatedAt,
        CreatedAt,N'AUTENTI,EKD,CALL',N'seed.extra',N'TEST',@Marker FROM @New;

    INSERT GenericSignatureTest.AutentiProcesses
        (EnvelopeId,ProcessId,AutentiEnvelopeStatus,DocumentId,DocumentTitle,IsActive,ExpirationDate)
    SELECT EnvelopeId,ProcessId,0,NEWID(),@Marker,1,DATEADD(day,30,CreatedAt) FROM @New;

    INSERT GenericSignatureTest.AutentiRecipients(EnvelopeId,Email,RecipientId,Status,Ai2Key)
    SELECT EnvelopeId,N'extra@example.invalid',NEWID(),0,N'EXTRA20230307' FROM @New;

    INSERT GenericSignatureTest.EkdProcesses
        (Id,CreationDate,UserLogin,UserName,CustomerNumber,CustomerName,CustomerId,
         CustomerAi2Key,StatusId,ProcessId,IsNewGenericSignature,IsActive,ExpirationDate)
    SELECT EkdId,CreatedAt,N'seed.extra',N'Test Extra',N'EXTRA',N'Synthetic Customer',NEWID(),
        N'EXTRA20230307',@Status,ProcessId,1,1,DATEADD(day,30,CreatedAt) FROM @New;

    INSERT GenericSignatureTest.EkdProcessHistories(ProcessId,Date,StatusId,UserLogin,UserName)
    SELECT EkdId,CreatedAt,@Status,N'seed.extra',N'Test Extra' FROM @New;

    INSERT GenericSignatureTest.CallProcesses(Id,ProcessId,DocumentId,DocumentTitle)
    SELECT NEWID(),ProcessId,NEWID(),@Marker FROM @New;

    INSERT GenericSignatureTest.ProcessData(Id,ProcessId,Ai2Key,DataType,Data)
    SELECT NEWID(),ProcessId,N'EXTRA20230307',N'EXTRA_PART_TEST',N'{"test":"late-arriving-data","day":"2023-03-07"}' FROM @New;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT @Marker AS BatchMarker,ProcessId,CreatedAt FROM @New ORDER BY Number;
SELECT N'Processes' AS TableName,COUNT(*) AS AddedRows FROM GenericSignatureTest.Processes p JOIN @New n ON n.ProcessId=p.Id
UNION ALL SELECT N'AutentiProcesses',COUNT(*) FROM GenericSignatureTest.AutentiProcesses p JOIN @New n ON n.EnvelopeId=p.EnvelopeId
UNION ALL SELECT N'AutentiRecipients',COUNT(*) FROM GenericSignatureTest.AutentiRecipients p JOIN @New n ON n.EnvelopeId=p.EnvelopeId
UNION ALL SELECT N'EkdProcesses',COUNT(*) FROM GenericSignatureTest.EkdProcesses p JOIN @New n ON n.EkdId=p.Id
UNION ALL SELECT N'EkdProcessHistories',COUNT(*) FROM GenericSignatureTest.EkdProcessHistories p JOIN @New n ON n.EkdId=p.ProcessId
UNION ALL SELECT N'CallProcesses',COUNT(*) FROM GenericSignatureTest.CallProcesses p JOIN @New n ON n.ProcessId=p.ProcessId
UNION ALL SELECT N'ProcessData',COUNT(*) FROM GenericSignatureTest.ProcessData p JOIN @New n ON n.ProcessId=p.ProcessId;
