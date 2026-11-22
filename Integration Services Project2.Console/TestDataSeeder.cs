using IntegrationServicesProject2.Database;
using Microsoft.Data.SqlClient;

namespace IntegrationServicesProject2.Console;

public sealed class TestDataSeeder
{
    public async Task SeedAsync(CancellationToken cancellationToken = default)
    {
        var builder = new SqlConnectionStringBuilder(DatabaseConfiguration.GetConnectionString())
        {
            InitialCatalog = "nito_superDb"
        };
        await using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandTimeout = 180;
        command.CommandText = await ReadScriptAsync("CreateArchiveJobRelations.sql", cancellationToken);
        await command.ExecuteNonQueryAsync(cancellationToken);

        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        command.Transaction = transaction;
        try
        {
            command.CommandText = await ReadScriptAsync("SeedAll.sql", cancellationToken);
            command.Parameters.Add("@DatabaseName", System.Data.SqlDbType.NVarChar, 128);
            foreach (var database in new[] { "nito_superDb", "nito_SomeApps" })
            {
                command.Parameters["@DatabaseName"].Value = database;
                await command.ExecuteNonQueryAsync(cancellationToken);
            }
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        command.Transaction = null;
        command.Parameters.Clear();
        command.CommandText = """
            SELECT DatabaseName, COUNT(*) AS Jobs,
                (SELECT COUNT(*) FROM Archive.ArchiveJobRelations r
                 WHERE r.DatabaseName=j.DatabaseName AND r.ChildTable LIKE N'ArchiveScenarioTest.%') AS Relations,
                CASE WHEN DatabaseName=N'nito_superDb' THEN
                    (SELECT SUM(p.rows) FROM nito_superDb.sys.tables t
                     JOIN nito_superDb.sys.schemas s ON s.schema_id=t.schema_id
                     JOIN nito_superDb.sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
                     WHERE s.name=N'ArchiveScenarioTest')
                ELSE
                    (SELECT SUM(p.rows) FROM nito_SomeApps.sys.tables t
                     JOIN nito_SomeApps.sys.schemas s ON s.schema_id=t.schema_id
                     JOIN nito_SomeApps.sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
                     WHERE s.name=N'ArchiveScenarioTest')
                END AS DataRows
            FROM Archive.ArchiveJobs j
            WHERE DatabaseName IN (N'nito_superDb',N'nito_SomeApps')
                AND TableName LIKE N'ArchiveScenarioTest.%'
            GROUP BY DatabaseName;
            """;
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            System.Console.WriteLine($"{reader.GetString(0)} | {reader.GetInt32(1)} zadań | {reader.GetInt32(2)} relacji | {reader.GetInt64(3)} rekordów testowych");
    }

    private static async Task<string> ReadScriptAsync(string name, CancellationToken cancellationToken)
    {
        using var stream = typeof(TestDataSeeder).Assembly.GetManifestResourceStream(
            $"IntegrationServicesProject2.Console.{name}")
            ?? throw new InvalidOperationException($"Brak skryptu {name}.");
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync(cancellationToken);
    }
}
