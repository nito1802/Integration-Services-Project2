using System.ComponentModel.DataAnnotations;

namespace IntegrationServicesProject2.Database.Entities;

public class ArchiveJob
{
    public int Id { get; set; }

    [Required, MaxLength(128)]
    public string DatabaseName { get; set; }

    [Required, MaxLength(128)]
    public string TableName { get; set; }

    [Required]
    public DateTime? LastSuccesProcessedAt { get; set; }

    [Required]
    public int ArchiveOlderThanDays { get; set; }
}