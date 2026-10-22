using Microsoft.Data.SqlClient;
using IntegrationServicesProject2.Database;

namespace IntegrationServicesProject2.Console;

public sealed class ForeignKeyTestDataCreator
{
    public async Task SeedAsync(CancellationToken cancellationToken = default)
    {
        var builder = new SqlConnectionStringBuilder(DatabaseConfiguration.GetConnectionString());
        builder.InitialCatalog = "nito_superDb";
        await using var connection = new SqlConnection(builder.ConnectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandTimeout = 120;
        using var stream = typeof(ForeignKeyTestDataCreator).Assembly.GetManifestResourceStream(
            "IntegrationServicesProject2.Console.SeedForeignKeyTables.sql")
            ?? throw new InvalidOperationException("Missing FK seed SQL resource.");
        using var text = new StreamReader(stream);
        command.CommandText = await text.ReadToEndAsync(cancellationToken);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
            System.Console.WriteLine($"Job {reader.GetInt32(0)} | {reader.GetString(1)} | {reader.GetInt32(2)} rows | {reader.GetDateTime(3):yyyy-MM-dd}–{reader.GetDateTime(4):yyyy-MM-dd} | {reader.GetInt32(5)} days");
    }
}
