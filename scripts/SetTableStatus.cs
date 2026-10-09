        public void Main()
        {
            // Run this step even when the export was skipped after an error.
            Dts.Variables["User::JobActive"].Value = false;
            Run(delegate {
                bool failed = Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value);
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveJobsDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand(@"
DECLARE @Now datetime2=SYSDATETIME();
UPDATE [Archive].[ArchiveJobs]
SET LastProcessedAt=@Now, LastProcessedStatus=CASE WHEN @Failed=1 THEN N'Error' ELSE N'Success' END,
    ErrorMessage=@Error, LastSuccesProcessedAt=CASE WHEN @Failed=0 THEN @Now ELSE LastSuccesProcessedAt END
WHERE Id=@Id;
IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;", connection))
                    {
                        command.Parameters.Add("@Id", SqlDbType.Int).Value = Dts.Variables["User::ArchiveJobId"].Value;
                        command.Parameters.Add("@Failed", SqlDbType.Bit).Value = failed;
                        command.Parameters.Add("@Error", SqlDbType.NVarChar, -1).Value = failed ? (object)Convert.ToString(Dts.Variables["User::JobError"].Value, CultureInfo.InvariantCulture) : DBNull.Value;
                        command.ExecuteNonQuery();
                    }
                }
                finally { Dts.Connections["ArchiveJobsDb"].ReleaseConnection(connection); }
                if (failed) Dts.Variables["User::FailedJobs"].Value = Convert.ToInt32(Dts.Variables["User::FailedJobs"].Value) + 1;
                bool again = false;
                Dts.Events.FireInformation(0, "CSV Archive", "Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; status=" + (failed ? "Error" : "Success") + "; path=" + Convert.ToString(Dts.Variables["User::OutputFile"].Value, CultureInfo.InvariantCulture), "", 0, ref again);
            });
        }
