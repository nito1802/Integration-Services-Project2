using IntegrationServicesProject2.Database.Consts;
using Microsoft.Extensions.Configuration;

namespace IntegrationServicesProject2.Database;

public static class DatabaseConfiguration
{
    public static string GetConnectionString()
    {
        IConfiguration configuration = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .Build();

        return configuration.GetConnectionString(DatabaseEnvironment.DatabaseConnectionString)
            ?? throw new InvalidOperationException("Set ConnectionStrings:ArchiveJobsDatabase in appsettings.json.");
    }
}
