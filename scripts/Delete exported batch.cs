        public void Main()
        {
            Run(delegate {
                var keys = (DataTable)Dts.Variables["User::BatchKeys"].Value;
                if (keys.Rows.Count == 0) return;
                int chunkSize = Math.Min(500, 2000 / keys.Columns.Count);
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    for (int start = 0; start < keys.Rows.Count; start += chunkSize)
                    {
                        using (var command = new SqlCommand())
                        {
                            command.Connection = connection;
                            command.CommandTimeout = 300;
                            var records = new List<string>();
                            int end = Math.Min(start + chunkSize, keys.Rows.Count);
                            for (int row = start; row < end; row++)
                            {
                                var fields = new List<string>();
                                foreach (DataColumn column in keys.Columns)
                                {
                                    string name = "@Key" + row + "_" + column.Ordinal;
                                    SqlParameter parameter = command.Parameters.Add(name, (SqlDbType)column.ExtendedProperties["SqlDbType"]);
                                    if (parameter.SqlDbType == SqlDbType.DateTime2 || parameter.SqlDbType == SqlDbType.DateTimeOffset || parameter.SqlDbType == SqlDbType.Time)
                                        parameter.Scale = 7;
                                    parameter.Value = keys.Rows[row][column];
                                    fields.Add(column.ColumnName + " = " + name);
                                }
                                records.Add("(" + string.Join(" AND ", fields.ToArray()) + ")");
                            }
                            command.CommandText = "SET NOCOUNT ON; DELETE FROM " + Convert.ToString(Dts.Variables["User::TableName"].Value) +
                                " WHERE " + string.Join(" OR ", records.ToArray()) + "; SELECT CONVERT(bigint, @@ROWCOUNT);";
                            long deleted = Convert.ToInt64(command.ExecuteScalar());
                            if (deleted != end - start) throw new InvalidOperationException("Deleted row count differs from the archived batch.");
                        }
                    }
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            });
        }
