using IntegrationServicesProject2.Database.Consts;
using IntegrationServicesProject2.Database.Entities;
using Microsoft.EntityFrameworkCore;

namespace IntegrationServicesProject2.Database;

public interface IArchiveJobsDbContext
{
    DbSet<ArchiveJob> ArchiveJobs { get; set; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}

public class ArchiveJobsDbContext : DbContext, IArchiveJobsDbContext
{
    public DbSet<ArchiveJob> ArchiveJobs { get; set; }

    public ArchiveJobsDbContext()
    {
    }

    public ArchiveJobsDbContext(DbContextOptions<ArchiveJobsDbContext> options) : base(options)
    {
    }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    {
        if (!optionsBuilder.IsConfigured)
        {
            optionsBuilder.UseSqlServer(DatabaseConfiguration.GetConnectionString(),
                sql => sql.MigrationsHistoryTable("__EFMigrationsHistory", DatabaseEnvironment.DatabaseSchema));
        }

        base.OnConfiguring(optionsBuilder);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(DatabaseEnvironment.DatabaseSchema);

        modelBuilder.Entity<ArchiveJob>(entity =>
        {

            // Fixed sample values keep future migrations deterministic.
            entity.HasData(
                new ArchiveJob { Id = 1, DatabaseName = "MyData", TableName = "MyData.Snapshots", LastSuccesProcessedAt = new DateOnly(2026, 9, 29), ArchiveOlderThanDays = 90 },
                new ArchiveJob { Id = 2, DatabaseName = "SmartHome", TableName = "SmartHome.Events", LastSuccesProcessedAt = new DateOnly(2026, 10, 3), ArchiveOlderThanDays = 30 },
                new ArchiveJob { Id = 3, DatabaseName = "SalesDemo", TableName = "dbo.Orders", LastSuccesProcessedAt = new DateOnly(2026, 9, 15), ArchiveOlderThanDays = 180 },
                new ArchiveJob { Id = 4, DatabaseName = "WarehouseDemo", TableName = "audit.StockMovements", LastSuccesProcessedAt = new DateOnly(2026, 10, 1), ArchiveOlderThanDays = 60 },
                new ArchiveJob { Id = 5, DatabaseName = "TelemetryDemo", TableName = "dbo.Readings", LastSuccesProcessedAt = new DateOnly(2026, 9, 22), ArchiveOlderThanDays = 14 },
                new ArchiveJob { Id = 6, DatabaseName = "SupportDemo", TableName = "dbo.Tickets", LastSuccesProcessedAt = new DateOnly(2026, 8, 31), ArchiveOlderThanDays = 365 },
                new ArchiveJob { Id = 7, DatabaseName = "PaymentsDemo", TableName = "audit.Transactions", LastSuccesProcessedAt = new DateOnly(2026, 10, 5), ArchiveOlderThanDays = 120 },
                new ArchiveJob { Id = 8, DatabaseName = "LogsDemo", TableName = "dbo.ApplicationLogs", LastSuccesProcessedAt = new DateOnly(2026, 10, 7), ArchiveOlderThanDays = 7 });
        });

        base.OnModelCreating(modelBuilder);
    }
}
