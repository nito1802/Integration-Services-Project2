-- Run in the configuration database after creating Archive.ArchiveJobs.
IF OBJECT_ID(N'Archive.ArchiveJobs', N'U') IS NULL
    THROW 50001, 'Archive.ArchiveJobs must exist.', 1;

SET XACT_ABORT ON;
BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'Archive.ArchiveJobRelations', N'U') IS NULL
        CREATE TABLE Archive.ArchiveJobRelations (
            Id int IDENTITY NOT NULL CONSTRAINT PK_ArchiveJobRelations PRIMARY KEY,
            ArchiveJobId int NOT NULL,
            ParentTable nvarchar(257) NOT NULL CONSTRAINT DF_ArchiveJobRelations_ParentTable DEFAULT N'',
            ChildTable nvarchar(257) NOT NULL,
            ParentKeyColumn sysname NOT NULL,
            ChildKeyColumn sysname NOT NULL,
            CONSTRAINT FK_ArchiveJobRelations_ArchiveJobs FOREIGN KEY (ArchiveJobId)
                REFERENCES Archive.ArchiveJobs(Id)
        );

    IF COL_LENGTH(N'Archive.ArchiveJobRelations', N'ChildSchema') IS NOT NULL
    BEGIN
        IF COL_LENGTH(N'Archive.ArchiveJobRelations', N'ParentTable') IS NULL
            ALTER TABLE Archive.ArchiveJobRelations ADD
                ParentSchema sysname NOT NULL CONSTRAINT DF_ArchiveJobRelations_ParentSchema DEFAULT N'',
                ParentTable sysname NOT NULL CONSTRAINT DF_ArchiveJobRelations_ParentTable DEFAULT N'';
        IF COL_LENGTH(N'Archive.ArchiveJobRelations', N'Id') IS NULL
        BEGIN
            ALTER TABLE Archive.ArchiveJobRelations ADD Id int IDENTITY NOT NULL;
            ALTER TABLE Archive.ArchiveJobRelations DROP CONSTRAINT PK_ArchiveJobRelations;
            ALTER TABLE Archive.ArchiveJobRelations ADD CONSTRAINT PK_ArchiveJobRelations PRIMARY KEY (Id);
        END;
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND name=N'UX_ArchiveJobRelations_Edge')
            DROP INDEX UX_ArchiveJobRelations_Edge ON Archive.ArchiveJobRelations;
        ALTER TABLE Archive.ArchiveJobRelations ALTER COLUMN ParentTable nvarchar(257) NOT NULL;
        ALTER TABLE Archive.ArchiveJobRelations ALTER COLUMN ChildTable nvarchar(257) NOT NULL;
        EXEC(N'UPDATE r SET ChildTable=r.ChildSchema+N''.''+r.ChildTable,
            ParentTable=CASE WHEN r.ParentTable=N'''' THEN j.TableName
                ELSE r.ParentSchema+N''.''+r.ParentTable END
            FROM Archive.ArchiveJobRelations r JOIN Archive.ArchiveJobs j ON j.Id=r.ArchiveJobId;');
        DECLARE @DefaultName sysname;
        SELECT @DefaultName=d.name FROM sys.default_constraints d
        JOIN sys.columns c ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
        WHERE d.parent_object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND c.name=N'ParentSchema';
        IF @DefaultName IS NOT NULL
        BEGIN
            DECLARE @DropDefault nvarchar(max)=N'ALTER TABLE Archive.ArchiveJobRelations DROP CONSTRAINT '+QUOTENAME(@DefaultName);
            EXEC sys.sp_executesql @DropDefault;
        END;
        ALTER TABLE Archive.ArchiveJobRelations DROP COLUMN ParentSchema,ChildSchema;
    END;
    IF COL_LENGTH(N'Archive.ArchiveJobRelations', N'DatabaseName') IS NULL
    BEGIN
        ALTER TABLE Archive.ArchiveJobRelations ADD DatabaseName nvarchar(128) NULL;
        EXEC(N'UPDATE r SET DatabaseName=j.DatabaseName FROM Archive.ArchiveJobRelations r
            JOIN Archive.ArchiveJobs j ON j.Id=r.ArchiveJobId;');
        ALTER TABLE Archive.ArchiveJobRelations ALTER COLUMN DatabaseName nvarchar(128) NOT NULL;
    END;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND name=N'UX_ArchiveJobRelations_Edge')
        EXEC(N'CREATE UNIQUE NONCLUSTERED INDEX UX_ArchiveJobRelations_Edge ON Archive.ArchiveJobRelations
            (ArchiveJobId,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)');
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
