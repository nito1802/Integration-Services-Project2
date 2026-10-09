        public void Main()
        {
            Dts.Variables["User::JobActive"].Value = false;
            Dts.Variables["User::JobFailed"].Value = false;
            Dts.Variables["User::JobError"].Value = "";
            Dts.Variables["User::OutputFile"].Value = "";
            SqlConnection status = (SqlConnection)Dts.Connections["ArchiveJobsDb"].AcquireConnection(Dts.Transaction);
            try
            {
                using (var command = new SqlCommand("UPDATE [Archive].[ArchiveJobs] SET ErrorMessage=NULL, LastProcessedAt=SYSDATETIME(), LastProcessedStatus=NULL WHERE Id=@Id; IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;", status))
                {
                    command.Parameters.Add("@Id", SqlDbType.Int).Value = Dts.Variables["User::ArchiveJobId"].Value;
                    command.ExecuteNonQuery();
                }
            }
            catch (Exception ex)
            {
                Dts.Events.FireError(0, "CSV Archive", "Cannot start archive job: " + ex, "", 0);
                Dts.TaskResult = (int)DTSExecResult.Failure;
                return;
            }
            finally { Dts.Connections["ArchiveJobsDb"].ReleaseConnection(status); }
            Dts.Variables["User::JobActive"].Value = true;
            Run(delegate {
                Dts.Variables["User::ArchiwumPath"].Value = Convert.ToString(Dts.Variables["$Package::ArchiveRoot"].Value);
                SqlConnection source = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    source.ChangeDatabase(Convert.ToString(Dts.Variables["User::DatabaseName"].Value, CultureInfo.InvariantCulture));
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(source); }
            });
        }
