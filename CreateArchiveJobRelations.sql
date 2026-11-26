-- Run in the database containing the Archive configuration schema.
-- Migrates existing job-bound relations to shared database/table relations.


Skrypt archiwizuje dane starsze niż ustawiona retencja. Dla każdego dnia eksportuje tabelę główną oraz jej powiązane dzieci do CSV, tworzy osobne ZIP-y dla tabel i sprawdza ich integralność. Dopiero po poprawnej weryfikacji całej grupy usuwa dane z bazy — najpierw dzieci, potem rodzica. Istniejące ZIP-y pozostają bez zmian, a kolejne eksporty tego samego dnia otrzymują końcówki __PART2, __PART3 itd.

Aby dodać własne dane do archiwizacji:
1. W Archive.ArchiveJobs dodaj wpis z nazwą bazy (DatabaseName), tabelą w formacie schema.Tabela (TableName), kolumną daty (DateColumn) i retencją w dniach (ArchiveOlderThanDays).
2. W Archive.ArchiveJobRelations zdefiniuj zależności: DatabaseName, ParentTable, ChildTable, ParentKeyColumn oraz ChildKeyColumn. Dodaj również kolejne poziomy dzieci; kolejność wpisów nie ma znaczenia. Dzieci nie potrzebują własnej kolumny daty — są wybierane przez powiązanie z archiwizowanymi rekordami.
3. Ustaw parametry pakietu: połączenie z serwerem, lokalizację tabel konfiguracji i folder archiwów. Opcjonalnie włącz logi szczegółowe i podsumowanie.
Przed eksportem skrypt sprawdza, czy konfiguracja obejmuje zależności FK wymagane do bezpiecznego usuwania. Tabele słownikowe lub inne rekordy wskazywane przez tabelę główną nie są automatycznie archiwizowane ani usuwane.



SET XACT_ABORT ON;
BEGIN TRANSACTION;
BEGIN TRY
    IF OBJECT_ID(N'Archive.ArchiveJobRelations', N'U') IS NULL
        CREATE TABLE Archive.ArchiveJobRelations (
            Id int IDENTITY NOT NULL CONSTRAINT PK_ArchiveJobRelations PRIMARY KEY,
            DatabaseName nvarchar(128) NOT NULL,
            ParentTable nvarchar(257) NOT NULL,
            ChildTable nvarchar(257) NOT NULL,
            ParentKeyColumn sysname NOT NULL,
            ChildKeyColumn sysname NOT NULL
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
    IF COL_LENGTH(N'Archive.ArchiveJobRelations', N'ArchiveJobId') IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND name=N'UX_ArchiveJobRelations_Edge')
            DROP INDEX UX_ArchiveJobRelations_Edge ON Archive.ArchiveJobRelations;
        EXEC(N'UPDATE r SET ParentTable=j.TableName
            FROM Archive.ArchiveJobRelations r JOIN Archive.ArchiveJobs j ON j.Id=r.ArchiveJobId
            WHERE NULLIF(LTRIM(RTRIM(r.ParentTable)),N'''') IS NULL;');
        DECLARE @ForeignKeys nvarchar(max)=N'';
        SELECT @ForeignKeys=@ForeignKeys+N'ALTER TABLE Archive.ArchiveJobRelations DROP CONSTRAINT '+QUOTENAME(f.name)+N';'
        FROM sys.foreign_keys f
        JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=f.object_id
        JOIN sys.columns c ON c.object_id=fc.parent_object_id AND c.column_id=fc.parent_column_id
        WHERE f.parent_object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND c.name=N'ArchiveJobId';
        IF @ForeignKeys<>N'' EXEC sys.sp_executesql @ForeignKeys;
        ALTER TABLE Archive.ArchiveJobRelations DROP COLUMN ArchiveJobId;
    END;

    -- Identical edges may have belonged to several jobs before the migration.
    ;WITH Duplicates AS (
        SELECT Id,ROW_NUMBER() OVER (
            PARTITION BY DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn
            ORDER BY Id
        ) AS Occurrence
        FROM Archive.ArchiveJobRelations
    )
    DELETE FROM Duplicates WHERE Occurrence>1;

    DECLARE @ParentDefault sysname;
    SELECT @ParentDefault=d.name FROM sys.default_constraints d
    JOIN sys.columns c ON c.object_id=d.parent_object_id AND c.column_id=d.parent_column_id
    WHERE d.parent_object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND c.name=N'ParentTable';
    IF @ParentDefault IS NOT NULL
    BEGIN
        DECLARE @DropParentDefault nvarchar(max)=N'ALTER TABLE Archive.ArchiveJobRelations DROP CONSTRAINT '+QUOTENAME(@ParentDefault);
        EXEC sys.sp_executesql @DropParentDefault;
    END;
    IF OBJECT_ID(N'Archive.CK_ArchiveJobRelations_ParentTable',N'C') IS NULL
        ALTER TABLE Archive.ArchiveJobRelations ADD CONSTRAINT CK_ArchiveJobRelations_ParentTable
            CHECK(NULLIF(LTRIM(RTRIM(ParentTable)),N'') IS NOT NULL);
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'Archive.ArchiveJobRelations') AND name=N'UX_ArchiveJobRelations_Edge')
        EXEC(N'CREATE UNIQUE NONCLUSTERED INDEX UX_ArchiveJobRelations_Edge ON Archive.ArchiveJobRelations
            (DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)');
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- Example only. Run separately in your configuration database:
/*
INSERT Archive.ArchiveJobRelations
    (DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
VALUES
    (N'aa360_genericsignature_dev01',N'dbo.Processes',N'dbo.AutentiProcesses',N'Id',N'ProcessId'),
    (N'aa360_genericsignature_dev01',N'dbo.AutentiProcesses',N'dbo.AutentiRecipients',N'EnvelopeId',N'EnvelopeId');
*/


INSERT INTO Archive.ArchiveJobRelations (
    DatabaseName,
    ParentTable,
    ChildTable,
    ParentKeyColumn,
    ChildKeyColumn
)
VALUES
(
    N'aa360_genericsignature_dev01',
    N'dbo.Processes',
    N'dbo.AutentiProcesses',
    N'Id',
    N'ProcessId'
),
(
    N'aa360_genericsignature_dev01',
    N'dbo.AutentiProcesses',
    N'dbo.AutentiRecipients',
    N'EnvelopeId',
    N'EnvelopeId'
);


INSERT INTO Archive.ArchiveJobs (
    DatabaseName,
    TableName,
    DateColumn,
    ArchiveOlderThanDays
)
VALUES (
    N'aa360_genericsignature_dev01',
    N'dbo.Processes',
    N'CreationDate',
    30
);



DECLARE @StartTable nvarchar(257) = N'dbo.Processes';
DECLARE @Children bit = 1;

DECLARE @RootId int = OBJECT_ID(@StartTable, N'U');

IF @RootId IS NULL
    THROW 50001, 'Nie znaleziono tabeli w bieżącej bazie.', 1;

;WITH Edges AS (
    SELECT
        fk.object_id AS ForeignKeyId,
        CASE WHEN @Children = 1
            THEN fk.referenced_object_id
            ELSE fk.parent_object_id
        END AS FromId,
        CASE WHEN @Children = 1
            THEN fk.parent_object_id
            ELSE fk.referenced_object_id
        END AS ToId
    FROM sys.foreign_keys fk
),
Dependencies AS (
    SELECT
        1 AS Depth,
        e.ForeignKeyId,
        e.ToId,
        CAST(
            '/' + CONVERT(varchar(11), @RootId) +
            '/' + CONVERT(varchar(11), e.ToId) + '/'
            AS varchar(max)
        ) AS ObjectPath,
        CAST(CASE WHEN e.ToId = @RootId THEN 1 ELSE 0 END AS bit) AS IsCycle
    FROM Edges e
    WHERE e.FromId = @RootId

    UNION ALL

    SELECT
        d.Depth + 1,
        e.ForeignKeyId,
        e.ToId,
        CAST(
            d.ObjectPath + CONVERT(varchar(11), e.ToId) + '/'
            AS varchar(max)
        ),
        CAST(CASE
            WHEN CHARINDEX(
                '/' + CONVERT(varchar(11), e.ToId) + '/',
                d.ObjectPath
            ) > 0 THEN 1 ELSE 0
        END AS bit)
    FROM Dependencies d
    JOIN Edges e ON e.FromId = d.ToId
    WHERE d.IsCycle = 0
)
SELECT
    d.Depth AS Poziom,
    fk.name AS ForeignKeyName,

    QUOTENAME(OBJECT_SCHEMA_NAME(fk.referenced_object_id)) +
        '.' + QUOTENAME(OBJECT_NAME(fk.referenced_object_id))
        AS ParentTable,

    COL_NAME(fc.referenced_object_id, fc.referenced_column_id)
        AS ParentKeyColumn,

    QUOTENAME(OBJECT_SCHEMA_NAME(fk.parent_object_id)) +
        '.' + QUOTENAME(OBJECT_NAME(fk.parent_object_id))
        AS ChildTable,

    COL_NAME(fc.parent_object_id, fc.parent_column_id)
        AS ChildKeyColumn,

    fc.constraint_column_id AS ColumnPosition,
    fk.delete_referential_action_desc AS DeleteRule,
    fk.is_disabled AS IsDisabled,
    d.IsCycle
FROM Dependencies d
JOIN sys.foreign_keys fk ON fk.object_id = d.ForeignKeyId
JOIN sys.foreign_key_columns fc
    ON fc.constraint_object_id = fk.object_id
ORDER BY
    d.Depth,
    ParentTable,
    ChildTable,
    ForeignKeyName,
    fc.constraint_column_id
OPTION (MAXRECURSION 32767);






------------------------


INSERT INTO Archive.ArchiveJobRelations (
    DatabaseName,
    ParentTable,
    ChildTable,
    ParentKeyColumn,
    ChildKeyColumn
)
VALUES
(
    N'360_genericsignature_dev01',
    N'dbo.Processes',
    N'dbo.AutentiProcesses',
    N'Id',
    N'ProcessId'
),
(
    N'360_genericsignature_dev01',
    N'dbo.Processes',
    N'dbo.CallProcesses',
    N'Id',
    N'ProcessId'
),
(
    N'360_genericsignature_dev01',
    N'dbo.Processes',
    N'dbo.EkProcesses',
    N'Id',
    N'ProcessId'
),
(
    N'360_genericsignature_dev01',
    N'dbo.Processes',
    N'dbo.ProcessData',
    N'Id',
    N'ProcessId'
),
(
    N'360_genericsignature_dev01',
    N'dbo.AutentiProcesses',
    N'dbo.AutentiRecipients',
    N'EnvelopeId',
    N'EnvelopeId'
),
(
    N'360_genericsignature_dev01',
    N'dbo.EkProcesses',
    N'dbo.EkProcessHistories',
    N'Id',
    N'ProcessId'
);