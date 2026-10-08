        public void Main()
        {
            Set("JobActive", false);
            Set("JobFailed", false);
            Set("JobError", "");
            Set("OutputFile", "");
            SqlConnection status = AcquireStatus();
            try
            {
                using (var command = new SqlCommand("UPDATE [Archive].[ArchiveJobs] SET ErrorMessage=NULL, LastProcessedAt=SYSDATETIME(), LastProcessedStatus=NULL WHERE Id=@Id; IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;", status))
                {
                    command.Parameters.Add("@Id", SqlDbType.Int).Value = V("ArchiveJobId");
                    command.ExecuteNonQuery();
                }
            }
            catch (Exception ex)
            {
                Dts.Events.FireError(0, "CSV Archive", "Cannot start archive job: " + ex, "", 0);
                Dts.TaskResult = (int)DTSExecResult.Failure;
                return;
            }
            finally { ReleaseStatus(status); }
            Set("JobActive", true);
            Run(delegate {
                Set("ArchiwumPath", Convert.ToString(Dts.Variables["$Package::ArchiveRoot"].Value));
                SqlConnection source = Acquire();
                try
                {
                    source.ChangeDatabase(S("DatabaseName"));
                }
                finally { Release(source); }
            });
        }
