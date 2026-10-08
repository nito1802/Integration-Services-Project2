using System;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Text;
using System.Globalization;
using System.Diagnostics;
using System.Collections.Generic;
using Microsoft.SqlServer.Dts.Runtime;

namespace __NAMESPACE__
{
    [Microsoft.SqlServer.Dts.Tasks.ScriptTask.SSISScriptTaskEntryPointAttribute]
    public partial class ScriptMain : Microsoft.SqlServer.Dts.Tasks.ScriptTask.VSTARTScriptObjectModelBase
    {
        private object V(string name) { return Dts.Variables["User::" + name].Value; }
        private void Set(string name, object value) { Dts.Variables["User::" + name].Value = value; }
        private string S(string name) { return Convert.ToString(V(name), CultureInfo.InvariantCulture); }
        private SqlConnection Acquire() { return (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction); }
        private void Release(SqlConnection connection) { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
        private SqlConnection AcquireStatus() { return (SqlConnection)Dts.Connections["ArchiveJobsDb"].AcquireConnection(Dts.Transaction); }
        private void ReleaseStatus(SqlConnection connection) { Dts.Connections["ArchiveJobsDb"].ReleaseConnection(connection); }
        private void Info(string message) { bool again = false; Dts.Events.FireInformation(0, "CSV Archive", message, "", 0, ref again); }
        private void Run(Action work)
        {
            if (Convert.ToBoolean(V("JobActive")) && Convert.ToBoolean(V("JobFailed")))
            {
                Dts.TaskResult = (int)DTSExecResult.Success;
                return;
            }
            try { work(); Dts.TaskResult = (int)DTSExecResult.Success; }
            catch (Exception ex)
            {
                if (!Convert.ToBoolean(V("JobActive")))
                {
                    Dts.Events.FireError(0, "CSV Archive", ex.ToString(), "", 0);
                    Dts.TaskResult = (int)DTSExecResult.Failure;
                    return;
                }
                Set("JobFailed", true);
                try
                {
                    SqlConnection source = Acquire();
                    try
                    {
                        using (var rollback = new SqlCommand("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;", source)) rollback.ExecuteNonQuery();
                    }
                    catch (Exception cleanupError) { Info("Rollback: " + cleanupError.Message); }
                    finally { Release(source); }
                }
                catch (Exception cleanupError) { Info("Source connection cleanup: " + cleanupError.Message); }
                string error = ex.ToString();
                if (Convert.ToBoolean(V("JobFilePublished")))
                {
                    try { File.Move(S("OutputFile"), S("OutputFile") + ".tmp"); Set("JobFilePublished", false); }
                    catch (Exception cleanupError) { error += "\nCSV cleanup: " + cleanupError; }
                }
                try
                {
                    SqlConnection status = AcquireStatus();
                    try
                    {
                        using (var command = new SqlCommand("UPDATE [Archive].[ArchiveJobs] SET LastProcessedAt=SYSDATETIME(), LastProcessedStatus=N'Error', ErrorMessage=@Error WHERE Id=@Id; IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;", status))
                        {
                            command.Parameters.Add("@Id", SqlDbType.Int).Value = V("ArchiveJobId");
                            command.Parameters.Add("@Error", SqlDbType.NVarChar, -1).Value = error;
                            command.ExecuteNonQuery();
                        }
                    }
                    finally { ReleaseStatus(status); }
                    Set("FailedJobs", Convert.ToInt32(V("FailedJobs")) + 1);
                    Dts.Events.FireWarning(0, "CSV Archive", "Job=" + V("ArchiveJobId") + "; table=" + S("TableName") + "; " + error, "", 0);
                    // Status is persisted; skip remaining work for this job and try the next one.
                    Dts.TaskResult = (int)DTSExecResult.Success;
                }
                catch (Exception statusError)
                {
                    Dts.Events.FireError(0, "CSV Archive", "Cannot persist job failure: " + statusError + "\nOriginal: " + error, "", 0);
                    Dts.TaskResult = (int)DTSExecResult.Failure;
                }
            }
        }
        private static string Quote(string identifier)
        {
            if (string.IsNullOrWhiteSpace(identifier) || identifier.Length > 128 || identifier.IndexOf('\0') >= 0)
                throw new ArgumentException("Invalid SQL identifier.");
            return "[" + identifier.Replace("]", "]]") + "]";
        }
        private static string[] TableParts(string name)
        {
            // Configuration uses unquoted schema.table (or table, with dbo as the default).
            string[] parts = name.Split('.');
            if (parts.Length == 1) return new string[] { "dbo", parts[0] };
            if (parts.Length != 2) throw new ArgumentException("TableName must be schema.table, without database/server qualifiers.");
            return parts;
        }
        private static void DateParameters(SqlCommand command, DateTime from, DateTime to)
        {
            command.Parameters.Add("@DateFrom", SqlDbType.DateTime2).Value = from;
            command.Parameters.Add("@DateTo", SqlDbType.DateTime2).Value = to;
        }
        private static string FolderName(string name)
        {
            // Reversible encoding prevents path traversal and collisions between SQL names.
            var encoded = new StringBuilder();
            foreach (char c in name)
                if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') encoded.Append(c);
                else encoded.Append("~" + ((int)c).ToString("X4", CultureInfo.InvariantCulture));
            return "table_" + encoded;
        }
        private static string EscapeCsv(string value)
        {
            if (value == null) return "\"\"";
            value = value.Replace("\"", "\"\"");
            return "\"" + value + "\"";
        }
        private static string CsvHeader(SqlDataReader reader)
        {
            var fields = new string[reader.FieldCount];
            for (int i = 0; i < fields.Length; i++) fields[i] = EscapeCsv(reader.GetName(i) + " (" + reader.GetDataTypeName(i) + ")");
            return string.Join(";", fields);
        }
        // __MAIN__
    }
}
