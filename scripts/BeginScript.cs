        public void Main()
        {
            Run(delegate {
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
                        var keys = new List<string>();
                        foreach (DataRow field in reader.GetSchemaTable().Rows)
                            if (Convert.ToBoolean(field["IsKey"])) keys.Add(Convert.ToString(field["ColumnName"]));
                        if (keys.Count == 0) throw new InvalidOperationException("No unique key: " + table);
                        Dts.Variables["User::OrderBy"].Value = string.Join(", ", keys.ToArray());
                    }
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }

                Dts.Variables["User::BeginScript"].Value =
                    "SET NOCOUNT ON; DECLARE @Cutoff date=DATEADD(day,-@Days,CONVERT(date,GETDATE())); " +
                    "DECLARE @First date=(SELECT CONVERT(date,MIN(" + column + ")) FROM " + table + " WHERE " + column + " < @Cutoff); " +
                    "SELECT CASE WHEN @First IS NULL THEN 0 ELSE DATEDIFF(day,@First,@Cutoff) END AS DaysCounter, " +
                    "COALESCE(@First,@Cutoff) AS DateFrom, @Cutoff AS DateTo;";
                Dts.Variables["User::LoopCounter"].Value = 0;
            });
        }
