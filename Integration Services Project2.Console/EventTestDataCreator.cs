using System.Data;
using IntegrationServicesProject2.Database;
using Microsoft.Data.SqlClient;

namespace IntegrationServicesProject2.Console;

public sealed class EventTestDataCreator
{
    // 20 days * 2500 rows = 50000 rows; three archive parts per day at batch size 1000.
    public async Task AddAsync(CancellationToken cancellationToken = default)
    {
        var marker = $"SSIS-TEST-{Guid.NewGuid():N}";
        await using var connection = new SqlConnection(DatabaseConfiguration.GetConnectionString());
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandTimeout = 120;
        command.CommandText = """
            SET NOCOUNT ON;
            SET XACT_ABORT ON;
            DECLARE @Inserted TABLE (Id int NOT NULL, CreatedAt datetime2 NOT NULL);
            BEGIN TRANSACTION;
            ;WITH Digits AS (
                SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) d(n)
            ), Numbers AS (
                SELECT a.n + 10*b.n + 100*c.n + 1000*d.n + 10000*e.n AS n
                FROM Digits a CROSS JOIN Digits b CROSS JOIN Digits c
                CROSS JOIN Digits d CROSS JOIN Digits e
            )
            INSERT INTO [SmartHome].[Events] ([Name], [Type], [ExecutedAt], [Comment], [CreatedAt], [ModifiedAt])
            OUTPUT inserted.Id, inserted.CreatedAt INTO @Inserted
            SELECT CASE WHEN n % 2 = 0 THEN N'OpenedExternally' ELSE N'ClosedExternally' END,
                   N'Door', dates.EventDate,
                   CONCAT(@Marker, N'; row=', n + 1), dates.EventDate, NULL
            FROM Numbers
            CROSS APPLY (SELECT DATEADD(second, (n % 2500) * 34,
                DATEADD(day, n / 2500, @StartDate)) AS EventDate) dates
            WHERE n < 50000;
            IF (SELECT COUNT(*) FROM @Inserted) <> 50000
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 50001, 'Expected exactly 50000 inserted events.', 1;
            END;
            COMMIT TRANSACTION;
            SELECT CAST(CreatedAt AS date) AS EventDay, COUNT(*) AS [RowCount],
                   MIN(Id) AS FirstId, MAX(Id) AS LastId
            FROM @Inserted
            GROUP BY CAST(CreatedAt AS date)
            ORDER BY EventDay;
            """;
        command.Parameters.Add("@Marker", SqlDbType.NVarChar, 64).Value = marker;
        command.Parameters.Add("@StartDate", SqlDbType.DateTime2).Value = new DateTime(2025, 1, 1);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        System.Console.WriteLine($"Znacznik danych testowych w Comment: {marker}");
        System.Console.WriteLine("Dzień (CreatedAt = ExecutedAt) | Liczba | Min ID | Max ID | Party po 1000");
        while (await reader.ReadAsync(cancellationToken))
        {
            System.Console.WriteLine($"{reader.GetDateTime(0):yyyy-MM-dd} | {reader.GetInt32(1)} | {reader.GetInt32(2)} | {reader.GetInt32(3)} | 3");
        }
        System.Console.WriteLine($"Dodano 50000 rekordów. Dokładny wybór: WHERE [Comment] LIKE N'{marker}; row=%'");
    }
}
