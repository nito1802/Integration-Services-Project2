using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace IntegrationServicesProject2.Database.Entities;

[Table("ArchiveJobs")]
public class ArchiveJob
{
    public int Id { get; set; }

    [Required, MaxLength(128)]
    public string DatabaseName { get; set; } = string.Empty;

    [Required, MaxLength(257)]
    public string TableName { get; set; } = string.Empty;

    [Column(TypeName = "datetime2")]
    public DateTime? LastSuccesProcessedAt { get; set; }

    [Required, MaxLength(128)]
    public string DateColumn { get; set; } = "CreatedAt";

    [Column(TypeName = "datetime2")]
    public DateTime? LastProcessedAt { get; set; }

    [MaxLength(16)]
    public ArchiveJobStatus? LastProcessedStatus { get; set; }

    public string? ErrorMessage { get; set; }

    [Required]
    public int ArchiveOlderThanDays { get; set; }
}
