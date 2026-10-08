        public void Main()
        {
            // Run this step even when the export was skipped after an error.
            Set("JobActive", false);
            Run(delegate {
                bool failed = Convert.ToBoolean(V("JobFailed"));
                SqlConnection connection = AcquireStatus();
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
                        command.Parameters.Add("@Id", SqlDbType.Int).Value = V("ArchiveJobId");
                        command.Parameters.Add("@Failed", SqlDbType.Bit).Value = failed;
                        command.Parameters.Add("@Error", SqlDbType.NVarChar, -1).Value = failed ? (object)S("JobError") : DBNull.Value;
                        command.ExecuteNonQuery();
                    }
                }
                finally { ReleaseStatus(connection); }
                if (failed) Set("FailedJobs", Convert.ToInt32(V("FailedJobs")) + 1);
                Info("Table=" + S("TableName") + "; status=" + (failed ? "Error" : "Success") + "; path=" + S("OutputFile"));
            });
        }
