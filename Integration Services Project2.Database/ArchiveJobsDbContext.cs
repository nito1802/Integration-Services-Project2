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

    public ArchiveJobsDbContext(DbContextOptions<ArchiveJobsDbContext> options) : base(options)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasDefaultSchema(DatabaseEnvironment.DatabaseSchema);
        modelBuilder.Entity<ArchiveJob>()
            .Property(job => job.LastProcessedStatus)
            .HasConversion<string>();

        // Jobs are live configuration. The initial migration seeds them;
        // later migrations must not overwrite processing results or remove jobs.
        base.OnModelCreating(modelBuilder);
    }
}