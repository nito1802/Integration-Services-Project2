        public void Main()
        {
            Run(delegate {
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand(S("CountSQL"), connection))
                    {
                        command.CommandTimeout = 300;
                        DateParameters(command, Convert.ToDateTime(V("CurrentDateFrom")), Convert.ToDateTime(V("CurrentDateTo")));
                        Set("FileRecordCounter", Convert.ToInt64(command.ExecuteScalar()));
                    }
                }
                finally { Release(connection); }
            });
        }
