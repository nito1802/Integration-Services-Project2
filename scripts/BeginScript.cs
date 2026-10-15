        public void Main()
        {
            string table = Convert.ToString(Dts.Variables["User::TableName"].Value);
            string column = Convert.ToString(Dts.Variables["User::ColumnDate"].Value);
            int days = Convert.ToInt32(Dts.Variables["User::Days"].Value);
            if (days <= 0) throw new ArgumentException("Days must be positive.");

            SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
            try
            {
                using (var command = new SqlCommand("SELECT TOP (0) * FROM " + table, connection))
                using (var reader = command.ExecuteReader(CommandBehavior.KeyInfo))
                {
                    Dts.Variables["User::TableSchema"].Value = reader.GetSchemaTable();
                    var keys = new List<string>();
                    foreach (DataRow field in reader.GetSchemaTable().Rows)
                        if (Convert.ToBoolean(field["IsKey"])) keys.Add(Convert.ToString(field["ColumnName"]));
                    if (keys.Count == 0) throw new InvalidOperationException("No unique key: " + table);
                    Dts.Variables["User::KeyColumns"].Value = string.Join(", ", keys.ToArray());
                }
            }
            finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }

            Dts.TaskResult = (int)DTSExecResult.Success;
        }
