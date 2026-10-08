using IntegrationServicesProject2.Database.Consts;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace IntegrationServicesProject2.Database;

public class ArchiveJobsDbContextFactory : IDesignTimeDbContextFactory<ArchiveJobsDbContext>
{
    public ArchiveJobsDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ArchiveJobsDbContext>()
            .UseSqlServer(DatabaseConfiguration.GetConnectionString(),
                sql => sql.MigrationsHistoryTable("__EFMigrationsHistory", DatabaseEnvironment.DatabaseSchema))
            .Options;

        return new ArchiveJobsDbContext(options);
    }
}
