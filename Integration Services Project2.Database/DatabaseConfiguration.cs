using IntegrationServicesProject2.Database.Consts;
using Microsoft.Extensions.Configuration;

namespace IntegrationServicesProject2.Database;

internal static class DatabaseConfiguration
{
    public static string GetConnectionString()
    {
        string? fromEnvironment = Environment.GetEnvironmentVariable(DatabaseEnvironment.ConnectionStringEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(fromEnvironment))
        {
            return fromEnvironment;
        }

        IConfiguration configuration = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.Local.json", optional: true)
            .Build();

        return configuration.GetConnectionString(DatabaseEnvironment.DatabaseConnectionString)
            ?? throw new InvalidOperationException("Set ConnectionStrings:ArchiveJobsDatabase or ARCHIVEJOBS_CONNECTION_STRING.");
    }
}
