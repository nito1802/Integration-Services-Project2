-- Opcjonalna konfiguracja wielu tabel. Uruchom ręcznie w bazie źródłowej.
-- Pakiet sam nie tworzy ani nie modyfikuje tabel konfiguracji.
IF OBJECT_ID(N'dbo.CasherSettings',N'U') IS NULL
BEGIN
    CREATE TABLE dbo.CasherSettings
    (
        Id int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        DictionaryType nvarchar(50) NOT NULL,
        TableName nvarchar(257) NOT NULL,
        Days int NOT NULL CHECK (Days > 0),
        ColumnDate nvarchar(128) NOT NULL,
        ArchiwumPath nvarchar(2048) NOT NULL
    );
END;
-- Przykład: dostosuj katalog do komputera wykonującego pakiet.
-- INSERT dbo.CasherSettings(DictionaryType,TableName,Days,ColumnDate,ArchiwumPath)
-- VALUES(N'Archiwum',N'MyData.Snapshots',90,N'CreatedAt',N'C:\Archive');
