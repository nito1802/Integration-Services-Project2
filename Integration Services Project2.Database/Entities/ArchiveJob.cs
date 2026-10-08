using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace IntegrationServicesProject2.Database.Entities;

[Table("ArchiveJobs")]
public class ArchiveJob
{
    [Key]
    [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
    public int Id { get; set; }

    [Required]
    [MaxLength(128)]
    public string DatabaseName { get; set; } = string.Empty;

    [Required]
    [MaxLength(257)]
    public string TableName { get; set; } = string.Empty;

    [Column(TypeName = "date")]
    public DateOnly LastSuccesProcessedAt { get; set; }

    public int ArchiveOlderThanDays { get; set; }
}
