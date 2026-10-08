namespace IntegrationServicesProject2.Database.Entities;

public class ArchiveJobEntity
{
    public int Id { get; set; }
    public string DatabaseName { get; set; } = string.Empty;
    public string TableName { get; set; } = string.Empty;
    public DateOnly LastSuccesProcessedAt { get; set; }
    public int ArchiveOlderThanDays { get; set; }
}
