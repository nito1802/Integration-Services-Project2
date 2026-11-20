using Microsoft.Data.SqlClient;
using IntegrationServicesProject2.Database;

namespace IntegrationServicesProject2.Console;

public sealed class ForeignKeyTestDataCreator
{
    public Task SeedAsync(CancellationToken cancellationToken = default)
        => RunSeedAsync(["SeedForeignKeyTables.sql"], cancellationToken);

    public Task SeedRelatedTablesAsync(CancellationToken cancellationToken = default)
        => RunSeedAsync(["CreateArchiveJobRelations.sql", "SeedRelatedTables.sql"], cancellationToken);

    private static async Task RunSeedAsync(string[] scripts, CancellationToken cancellationToken)
    {
        var builder = new SqlConnectionStringBuilder(DatabaseConfiguration.GetConnectionString());
        builder.InitialCatalog = "nito_superDb";
        await using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandTimeout = 120;
        var sql = new List<string>();
        foreach (var script in scripts)
        {
            using var stream = typeof(ForeignKeyTestDataCreator).Assembly.GetManifestResourceStream(
                $"IntegrationServicesProject2.Console.{script}")
                ?? throw new InvalidOperationException($"Missing SQL resource: {script}.");
            using var text = new StreamReader(stream);
            sql.Add(await text.ReadToEndAsync(cancellationToken));
        }
        command.CommandText = string.Join(Environment.NewLine, sql);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            System.Console.WriteLine($"Job {reader.GetInt32(0)} | {reader.GetString(1)} | {reader.GetInt32(2)} rows | {reader.GetDateTime(3):yyyy-MM-dd}–{reader.GetDateTime(4):yyyy-MM-dd} | {reader.GetInt32(5)} days");
    }
}
