        public void Main()
        {
            Run(delegate {
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand(S("BeginScript"), connection))
                    {
                        command.CommandTimeout = 300;
                        command.Parameters.Add("@Days", SqlDbType.Int).Value = V("Days");
                        using (var reader = command.ExecuteReader())
                        {
                            if (!reader.Read()) throw new InvalidOperationException("Missing table range result.");
                            Set("DaysCounter", reader.GetInt32(0));
                            Set("DateFrom", reader.GetDateTime(1));
                            Set("DateTo", reader.GetDateTime(2));
                            Set("TableExpectedRows", reader.GetInt64(3));
                        }
                    }
                }
                finally { Release(connection); }
            });
        }
