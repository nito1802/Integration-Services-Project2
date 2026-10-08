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

    //public ArchiveJobsDbContext()
    //{
    //}

    public ArchiveJobsDbContext(DbContextOptions<ArchiveJobsDbContext> options) : base(options)
    {
    }

    //protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    //{
    //    if (!optionsBuilder.IsConfigured)
    //    {
    //        optionsBuilder.UseSqlServer(DatabaseConfiguration.GetConnectionString());
    //    }

    //    base.OnConfiguring(optionsBuilder);
    //}

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(DatabaseEnvironment.DatabaseSchema);

        modelBuilder.Entity<ArchiveJob>(entity =>
        {
            // Fixed sample values keep future migrations deterministic.
            entity.HasData(
                new ArchiveJob { Id = 1, DatabaseName = "MyData", TableName = "MyData.Snapshots", LastSuccesProcessedAt = DateTime.Now, ArchiveOlderThanDays = 90 },
                new ArchiveJob { Id = 2, DatabaseName = "SmartHome", TableName = "SmartHome.Events", LastSuccesProcessedAt = DateTime.Now, ArchiveOlderThanDays = 30 }
            );
        });

        base.OnModelCreating(modelBuilder);
    }
}