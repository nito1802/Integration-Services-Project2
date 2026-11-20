-- Run in the configuration database after creating Archive.ArchiveJobs.
IF OBJECT_ID(N'Archive.ArchiveJobs', N'U') IS NULL
    THROW 50001, 'Archive.ArchiveJobs must exist.', 1;

IF OBJECT_ID(N'Archive.ArchiveJobRelations', N'U') IS NULL
BEGIN
    CREATE TABLE Archive.ArchiveJobRelations (
        ArchiveJobId int NOT NULL,
        ChildSchema sysname NOT NULL,
        ChildTable sysname NOT NULL,
        ParentKeyColumn sysname NOT NULL,
        ChildKeyColumn sysname NOT NULL,
        CONSTRAINT PK_ArchiveJobRelations PRIMARY KEY (ArchiveJobId, ChildSchema, ChildTable),
        CONSTRAINT FK_ArchiveJobRelations_ArchiveJobs FOREIGN KEY (ArchiveJobId)
            REFERENCES Archive.ArchiveJobs(Id)
    );
END;
