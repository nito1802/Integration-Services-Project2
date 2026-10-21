-- Uruchom w bazie konfiguracji wskazanej przez ArchiveJobsConnectionString.
-- Tworzy aktualna strukture bez migracji EF i bez przykladowych zadan.
-- Istniejaca tabela pozostaje bez zmian; skrypt nie aktualizuje starszej struktury.
-- ArchiveJobStatus jest enumem C#, a nie osobna tabela:
-- LastProcessedStatus przechowuje N'Error', N'Success' albo NULL.

DECLARE @SchemaName sysname=N'Archive';
DECLARE @TableName sysname=N'ArchiveJobs';
-- Schema musi juz istniec. Ustaw ArchiveJobsTable pakietu na te same schema.table.
IF NULLIF(LTRIM(RTRIM(@SchemaName)),N'') IS NULL OR NULLIF(LTRIM(RTRIM(@TableName)),N'') IS NULL
    THROW 50001,'Schema and table names must not be empty.',1;
IF SCHEMA_ID(@SchemaName) IS NULL
    THROW 50002,'The configured schema does not exist. Select an existing schema.',1;

SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @QualifiedName nvarchar(517)=QUOTENAME(@SchemaName)+N'.'+QUOTENAME(@TableName);
IF OBJECT_ID(@QualifiedName,N'U') IS NULL
BEGIN
    DECLARE @Sql nvarchar(max)=N'CREATE TABLE '+@QualifiedName+N'
    (
        [Id] int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [DatabaseName] nvarchar(128) NOT NULL,
        [TableName] nvarchar(257) NOT NULL,
        [LastSuccesProcessedAt] datetime2(7) NULL,
        [DateColumn] nvarchar(128) NOT NULL,
        [LastProcessedAt] datetime2(7) NULL,
        [LastProcessedStatus] nvarchar(16) NULL,
        [ErrorMessage] nvarchar(max) NULL,
        [ArchiveOlderThanDays] int NOT NULL
    );';
    EXEC sys.sp_executesql @Sql;
END;
COMMIT TRANSACTION;
