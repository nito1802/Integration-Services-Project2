-- Uruchom w bazie konfiguracji wskazanej przez ArchiveJobsConnectionString.
-- Tworzy aktualna strukture bez migracji EF i bez przykladowych zadan.
-- Istniejaca tabela pozostaje bez zmian; skrypt nie aktualizuje starszej struktury.
-- ArchiveJobStatus jest enumem C#, a nie osobna tabela:
-- LastProcessedStatus przechowuje N'Error', N'Success' albo NULL.

SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF SCHEMA_ID(N'Archive') IS NULL
    EXEC(N'CREATE SCHEMA [Archive]');

IF OBJECT_ID(N'[Archive].[ArchiveJobs]', N'U') IS NULL
BEGIN
    CREATE TABLE [Archive].[ArchiveJobs]
    (
        [Id] int IDENTITY(1,1) NOT NULL,
        [DatabaseName] nvarchar(128) NOT NULL,
        [TableName] nvarchar(257) NOT NULL,
        [LastSuccesProcessedAt] datetime2(7) NULL,
        [DateColumn] nvarchar(128) NOT NULL,
        [LastProcessedAt] datetime2(7) NULL,
        [LastProcessedStatus] nvarchar(16) NULL,
        [ErrorMessage] nvarchar(max) NULL,
        [ArchiveOlderThanDays] int NOT NULL,

        CONSTRAINT [PK_ArchiveJobs] PRIMARY KEY ([Id])
    );
END;

COMMIT TRANSACTION;
