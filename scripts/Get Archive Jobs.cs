        public void Main()
        {
            Run(delegate {
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveJobsDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand("SELECT Id, DatabaseName, TableName, ArchiveOlderThanDays, DateColumn FROM [Archive].[ArchiveJobs] ORDER BY Id;", connection))
                    using (var adapter = new SqlDataAdapter(command))
                    {
                        var jobs = new DataSet();
                        adapter.Fill(jobs);
                        Dts.Variables["User::Tables"].Value = jobs;
                    }
                }
                finally { Dts.Connections["ArchiveJobsDb"].ReleaseConnection(connection); }
            });
        }
