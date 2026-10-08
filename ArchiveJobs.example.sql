-- Tabele i migracje tworzy biblioteka .Database.
-- Przykład nowego zadania w bazie konfiguracji; dostosuj bazę, tabelę i kolumnę daty.
-- Nie wykonuj ponownie dla już istniejącego zadania.
-- INSERT [Archive].[ArchiveJobs]
--     (DatabaseName, TableName, DateColumn, ArchiveOlderThanDays)
-- VALUES (DB_NAME(), N'MyData.Snapshots', N'CreatedAt', 90);

SELECT Id, DatabaseName, TableName, DateColumn, ArchiveOlderThanDays,
       LastSuccesProcessedAt, LastProcessedAt, LastProcessedStatus, ErrorMessage
FROM [Archive].[ArchiveJobs]
ORDER BY Id;
