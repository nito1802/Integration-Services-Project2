namespace ArchiveRelationsGenerator.Core;

public static class SampleData
{
    public static string Text => string.Join(Environment.NewLine, new[]
    {
        "Poziom\tForeignKeyName\tParentTable\tParentKeyColumn\tChildTable\tChildKeyColumn\tColumnPosition\tDeleteRule\tIsDisabled\tIsCycle",
        "1\tFK_AutentiProcesses_Processes_ProcessId\t[GenericSignatureTest].[Processes]\tId\t[GenericSignatureTest].[AutentiProcesses]\tProcessId\t1\tNO_ACTION\t0\t0",
        "1\tFK_CallProcesses_Processes_ProcessId\t[GenericSignatureTest].[Processes]\tId\t[GenericSignatureTest].[CallProcesses]\tProcessId\t1\tCASCADE\t0\t0",
        "1\tFK_EkdProcesses_Processes_ProcessId\t[GenericSignatureTest].[Processes]\tId\t[GenericSignatureTest].[EkdProcesses]\tProcessId\t1\tNO_ACTION\t0\t0",
        "1\tFK_ProcessData_Processes_ProcessId\t[GenericSignatureTest].[Processes]\tId\t[GenericSignatureTest].[ProcessData]\tProcessId\t1\tCASCADE\t0\t0",
        "2\tFK_AutentiRecipients_AutentiProcesses_EnvelopeId\t[GenericSignatureTest].[AutentiProcesses]\tEnvelopeId\t[GenericSignatureTest].[AutentiRecipients]\tEnvelopeId\t1\tCASCADE\t0\t0",
        "2\tFK_EkdProcessHistories_EkdProcesses_ProcessId\t[GenericSignatureTest].[EkdProcesses]\tId\t[GenericSignatureTest].[EkdProcessHistories]\tProcessId\t1\tCASCADE\t0\t0"
    });
}
