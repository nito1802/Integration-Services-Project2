        public void Main()
        {
            Run(delegate {
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand(Convert.ToString(Dts.Variables["User::BeginScript"].Value, CultureInfo.InvariantCulture), connection))
                    {
                        command.CommandTimeout = 300;
                        command.Parameters.Add("@Days", SqlDbType.Int).Value = Dts.Variables["User::Days"].Value;
                        using (var reader = command.ExecuteReader())
                        {
                            if (!reader.Read()) throw new InvalidOperationException("Missing table range result.");
                            Dts.Variables["User::DaysCounter"].Value = reader.GetInt32(0);
                            Dts.Variables["User::DateFrom"].Value = reader.GetDateTime(1);
                            Dts.Variables["User::DateTo"].Value = reader.GetDateTime(2);
                        }
                    }
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            });
        }
