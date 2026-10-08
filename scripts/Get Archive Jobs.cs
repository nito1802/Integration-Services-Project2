        public void Main()
        {
            Run(delegate {
                SqlConnection connection = AcquireStatus();
                try
                {
                    using (var command = new SqlCommand("SELECT Id, DatabaseName, TableName, ArchiveOlderThanDays, DateColumn FROM [Archive].[ArchiveJobs] ORDER BY Id;", connection))
                    using (var adapter = new SqlDataAdapter(command))
                    {
                        var jobs = new DataSet();
                        adapter.Fill(jobs);
                        Set("Tables", jobs);
                    }
                }
                finally { ReleaseStatus(connection); }
            });
        }
