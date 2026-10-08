BEGIN TRANSACTION;
DECLARE @var nvarchar(max);
SELECT @var = QUOTENAME([d].[name])
FROM [sys].[default_constraints] [d]
INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
WHERE ([d].[parent_object_id] = OBJECT_ID(N'[Archive].[ArchiveJobs]') AND [c].[name] = N'LastSuccesProcessedAt');
IF @var IS NOT NULL EXEC(N'ALTER TABLE [Archive].[ArchiveJobs] DROP CONSTRAINT ' + @var + ';');
ALTER TABLE [Archive].[ArchiveJobs] ALTER COLUMN [LastSuccesProcessedAt] datetime2 NULL;

ALTER TABLE [Archive].[ArchiveJobs] ADD [DateColumn] nvarchar(128) NOT NULL DEFAULT N'CreatedAt';

ALTER TABLE [Archive].[ArchiveJobs] ADD [ErrorMessage] nvarchar(max) NULL;

ALTER TABLE [Archive].[ArchiveJobs] ADD [LastProcessedAt] datetime2 NULL;

ALTER TABLE [Archive].[ArchiveJobs] ADD [LastProcessedStatus] nvarchar(16) NULL;

UPDATE [Archive].[ArchiveJobs] SET [DatabaseName]=DB_NAME() WHERE ([DatabaseName]=N'MyData' AND [TableName]=N'MyData.Snapshots') OR ([DatabaseName]=N'SmartHome' AND [TableName]=N'SmartHome.Events');

INSERT INTO [Archive].[__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'20261008131331_AddArchiveJobProcessingState', N'10.0.3');

COMMIT;
GO

