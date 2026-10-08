using IntegrationServicesProject2.Database;
using IntegrationServicesProject2.Database.Entities;

namespace IntegrationServicesProject2.Console;

public sealed class ArchiveJobCreator(ArchiveJobsDbContext dbContext)
{
    public async Task AddAsync(List<ArchiveJob> jobs)
    {
        dbContext.ArchiveJobs.AddRange(jobs);
        await dbContext.SaveChangesAsync();
    }
}