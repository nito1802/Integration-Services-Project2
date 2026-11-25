using System.ComponentModel.DataAnnotations;

namespace IntegrationServicesProject2.Console.GenericSignature;

// Independent load fixture; not part of the Process relation graph.
public class ExportLoadRecord
{
    public long Id { get; set; }
    public DateTime CreatedAt { get; set; }
    [Required, MaxLength(128)] public string Payload { get; set; } = "";
}

public enum AutentiEnvelopeStatus { Created, Sent, Signed, Rejected }
public enum AutentiRecipientStatus { Pending, Notified, Signed, Rejected }
// The photos show these navigations, but not the dictionary definitions.
public class NewProcessType { [MaxLength(30)] public string Id { get; set; } = ""; [MaxLength(128)] public string Name { get; set; } = ""; }
public class EkdStatus { [MaxLength(64)] public string Id { get; set; } = ""; [MaxLength(128)] public string Name { get; set; } = ""; }
public class Process
{
    public Guid Id { get; set; }
    [Required, MaxLength(30)] public string ProcessTypeId { get; set; } = "";
    public NewProcessType ProcessType { get; set; } = null!;
    [MaxLength(50)] public string? SignatureTypeId { get; set; }
    [MaxLength(17)] public string? Ai2Key { get; set; }
    public string? EqNumber { get; set; }
    [Required, MaxLength(50)] public string Status { get; set; } = "";
    public DateTime CreationDate { get; set; }
    public DateTime? SignatureTypeSelectionDate { get; set; }
    public string? AvailableSignatureTypes { get; set; }
    [Required, MaxLength(128)] public string UserLogin { get; set; } = "";
    [Required, MaxLength(64)] public string ClientWorkingMode { get; set; } = "";
    public string? ExternalId { get; set; }
    public List<AutentiProcess> AutentiProcesses { get; set; } = [];
    public List<EkdProcess> EkdProcesses { get; set; } = [];
    public List<CallProcess> CallProcesses { get; set; } = [];
    public List<ProcessData> ProcessData { get; set; } = [];
}
public class AutentiProcess
{
    [MaxLength(450)] public string EnvelopeId { get; set; } = "";
    public Guid? ProcessId { get; set; }
    public Process? Process { get; set; }
    public AutentiEnvelopeStatus AutentiEnvelopeStatus { get; set; }
    public List<AutentiRecipient> AutentiRecipients { get; set; } = [];
    [MaxLength(128)] public string? DocuwareName { get; set; }
    [MaxLength(32)] public string? DocuwareFile { get; set; }
    [MaxLength(128)] public string? DocuwareDescription { get; set; }
    public Guid DocumentId { get; set; }
    [Required, MaxLength(256)] public string DocumentTitle { get; set; } = "";
    public string? DocuwareIndexesJson { get; set; }
    public int? DocuwareId { get; set; }
    public bool IsActive { get; set; }
    public DateTime? ExpirationDate { get; set; }
}
public class AutentiRecipient
{
    public Guid RecipientId { get; set; }
    [MaxLength(450)] public string EnvelopeId { get; set; } = "";
    [Required, MaxLength(256)] public string Email { get; set; } = "";
    public AutentiRecipientStatus Status { get; set; }
    public AutentiProcess AutentiProcess { get; set; } = null!;
    [MaxLength(17)] public string? Ai2Key { get; set; }
}
public class CallProcess
{
    public Guid Id { get; set; }
    public Guid ProcessId { get; set; }
    public Process Process { get; set; } = null!;
    [MaxLength(128)] public string? DocuwareName { get; set; }
    [MaxLength(32)] public string? DocuwareFile { get; set; }
    [MaxLength(128)] public string? DocuwareDescription { get; set; }
    public Guid DocumentId { get; set; }
    [Required, MaxLength(256)] public string DocumentTitle { get; set; } = "";
    public int? DocuwareId { get; set; }
}
public class ProcessData
{
    public Guid Id { get; set; }
    public Guid ProcessId { get; set; }
    public Process Process { get; set; } = null!;
    [MaxLength(17)] public string? Ai2Key { get; set; }
    [Required, MaxLength(100)] public string DataType { get; set; } = "";
    [Required] public string Data { get; set; } = "";
}
public class EkdProcess
{
    public Guid Id { get; set; }
    public Guid? ExternalId { get; set; }
    public DateTime CreationDate { get; set; }
    [Required, MaxLength(128)] public string UserLogin { get; set; } = "";
    [Required, MaxLength(128)] public string UserName { get; set; } = "";
    [Required, MaxLength(6)] public string CustomerNumber { get; set; } = "";
    [Required, MaxLength(128)] public string CustomerName { get; set; } = "";
    [MaxLength(11)] public string? CustomerPesel { get; set; }
    [MaxLength(128)] public string? CustomerEmail { get; set; }
    public Guid CustomerId { get; set; }
    [Required, MaxLength(17)] public string CustomerAi2Key { get; set; } = "";
    [Required, MaxLength(64)] public string StatusId { get; set; } = "";
    public EkdStatus Status { get; set; } = null!;
    public List<EkdProcessHistory> ProcessHistories { get; set; } = [];
    public DateTime? SentDate { get; set; }
    public int? DocuwareId { get; set; }
    [MaxLength(32)] public string? DocuwareFile { get; set; }
    [MaxLength(6)] public string? CompanyNumber { get; set; }
    public string? UploadDocumentUrl { get; set; }
    public string? AcceptanceChannel { get; set; }
    public DateTime? DecisionDate { get; set; }
    public Guid? ProcessId { get; set; }
    public Process? Process { get; set; }
    public bool IsNewGenericSignature { get; set; }
    public Guid? DocumentId { get; set; }
    public bool IsActive { get; set; }
    public DateTime ExpirationDate { get; set; }
}
public class EkdProcessHistory
{
    public long Id { get; set; }
    public Guid ProcessId { get; set; }
    public EkdProcess Process { get; set; } = null!;
    public DateTime Date { get; set; }
    [Required, MaxLength(64)] public string StatusId { get; set; } = "";
    public EkdStatus Status { get; set; } = null!;
    [Required, MaxLength(128)] public string UserLogin { get; set; } = "";
    [Required, MaxLength(128)] public string UserName { get; set; } = "";
}
