using Microsoft.EntityFrameworkCore;

namespace IntegrationServicesProject2.Console.GenericSignature;

public sealed class GenericSignatureDbContext(DbContextOptions<GenericSignatureDbContext> options) : DbContext(options)
{
    public const string Schema = "GenericSignatureTest";
    public DbSet<Process> Processes => Set<Process>();
    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasDefaultSchema(Schema);
        b.Entity<ExportLoadRecord>().ToTable("ExportLoadTest").HasKey(x => x.Id);
        b.Entity<ExportLoadRecord>().Property(x => x.Id).ValueGeneratedNever();
        b.Entity<ExportLoadRecord>().HasIndex(x => x.CreatedAt);
        b.Entity<Process>().ToTable("Processes");
        b.Entity<Document>().ToTable("Documents");
        b.Entity<Process>().HasOne(x => x.Document).WithMany().HasForeignKey(x => x.DocumentId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<AutentiProcess>().ToTable("AutentiProcesses").HasKey(x => x.EnvelopeId);
        b.Entity<AutentiRecipient>().ToTable("AutentiRecipients").HasKey(x => new { x.EnvelopeId, x.Email });
        b.Entity<CallProcess>().ToTable("CallProcesses");
        b.Entity<ProcessData>().ToTable("ProcessData");
        b.Entity<EkdProcess>().ToTable("EkdProcesses");
        b.Entity<EkdProcessHistory>().ToTable("EkdProcessHistories");
        b.Entity<NewProcessType>().ToTable("ProcessTypes");
        b.Entity<EkdStatus>().ToTable("EkdStatuses");
        b.Entity<Process>().HasOne(x => x.ProcessType).WithMany().HasForeignKey(x => x.ProcessTypeId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<AutentiProcess>().HasOne(x => x.Process).WithMany(x => x.AutentiProcesses).HasForeignKey(x => x.ProcessId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<AutentiRecipient>().HasOne(x => x.AutentiProcess).WithMany(x => x.AutentiRecipients).HasForeignKey(x => x.EnvelopeId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<EkdProcess>().HasOne(x => x.Process).WithMany(x => x.EkdProcesses).HasForeignKey(x => x.ProcessId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<CallProcess>().HasOne(x => x.Process).WithMany(x => x.CallProcesses).HasForeignKey(x => x.ProcessId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<ProcessData>().HasOne(x => x.Process).WithMany(x => x.ProcessData).HasForeignKey(x => x.ProcessId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<EkdProcessHistory>().HasOne(x => x.Process).WithMany(x => x.ProcessHistories).HasForeignKey(x => x.ProcessId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<EkdProcess>().HasOne(x => x.Status).WithMany().HasForeignKey(x => x.StatusId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<EkdProcessHistory>().HasOne(x => x.Status).WithMany().HasForeignKey(x => x.StatusId).OnDelete(DeleteBehavior.NoAction);
        b.Entity<Process>().HasIndex(x => x.CreationDate);
    }
}
