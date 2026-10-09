        public void Main()
        {
            Run(delegate {
                string[] parts = Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture).Split('.');
                if (parts.Length == 1) parts = new string[] { "dbo", parts[0] };
                if (parts.Length != 2) throw new ArgumentException("TableName must be schema.table, without database/server qualifiers.");
                foreach (string part in parts)
                    if (string.IsNullOrWhiteSpace(part) || part.Length > 128 || part.IndexOf('\0') >= 0)
                        throw new ArgumentException("Invalid SQL identifier.");
                string table = "[" + parts[0].Replace("]", "]]") + "].[" + parts[1].Replace("]", "]]") + "]";
                string column = Convert.ToString(Dts.Variables["User::ColumnDate"].Value, CultureInfo.InvariantCulture);
                if (string.IsNullOrWhiteSpace(column) || column.Length > 128 || column.IndexOf('\0') >= 0)
                    throw new ArgumentException("Invalid SQL identifier.");
                string quotedColumn = "[" + column.Replace("]", "]]") + "]";
                int days = Convert.ToInt32(Dts.Variables["User::Days"].Value);
                if (days <= 0) throw new ArgumentException("Days must be positive: 90 means full days older than 90 days.");
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand(@"
SELECT c.name, TYPE_NAME(c.system_type_id) AS TypeName
FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id
WHERE t.object_id=OBJECT_ID(@TableName) AND c.name=@ColumnName;", connection))
                    {
                        command.Parameters.Add("@TableName", SqlDbType.NVarChar, 300).Value = table;
                        command.Parameters.Add("@ColumnName", SqlDbType.NVarChar, 128).Value = column;
                        using (var reader = command.ExecuteReader())
                        {
                            if (!reader.Read()) throw new ArgumentException("Table/date column not found: " + table + "." + quotedColumn);
                            string type = reader.GetString(1);
                            if (type != "date" && type != "datetime" && type != "datetime2" && type != "smalldatetime")
                                throw new ArgumentException("Unsupported date column type: " + type);
                        }
                    }
                    var keys = new List<string>();
                    using (var command = new SqlCommand(@"
SELECT c.name FROM sys.index_columns ic JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE ic.object_id=OBJECT_ID(@TableName) AND ic.key_ordinal>0 AND ic.index_id=(
 SELECT TOP (1) i.index_id FROM sys.indexes i
 WHERE i.object_id=OBJECT_ID(@TableName) AND i.is_unique=1 AND i.has_filter=0 AND i.is_disabled=0 AND i.is_hypothetical=0
 ORDER BY i.is_primary_key DESC,i.index_id) ORDER BY ic.key_ordinal;", connection))
                    {
                        command.Parameters.Add("@TableName", SqlDbType.NVarChar, 300).Value = table;
                        using (var reader = command.ExecuteReader())
                            while (reader.Read()) keys.Add("[" + reader.GetString(0).Replace("]", "]]") + "]");
                    }
                    if (keys.Count == 0) throw new InvalidOperationException("No unfiltered unique key: " + table);
                    Dts.Variables["User::OrderBy"].Value = string.Join(", ", keys.ToArray());
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
                Dts.Variables["User::QuotedTable"].Value = table;
                Dts.Variables["User::QuotedColumn"].Value = quotedColumn;
                Dts.Variables["User::BeginScript"].Value = "SET NOCOUNT ON; DECLARE @Cutoff date=DATEADD(day,-@Days,CONVERT(date,GETDATE())); " +
                    "DECLARE @First date=(SELECT CONVERT(date,MIN(" + quotedColumn + ")) FROM " + table + " WHERE " + quotedColumn + " < @Cutoff); " +
                    "SELECT CASE WHEN @First IS NULL THEN 0 ELSE DATEDIFF(day,@First,@Cutoff) END AS DaysCounter, " +
                    "COALESCE(@First,@Cutoff) AS DateFrom, @Cutoff AS DateTo;";
                Dts.Variables["User::LoopCounter"].Value = 0;
                bool again = false;
                Dts.Events.FireInformation(0, "CSV Archive", "Table=" + table + "; Days=" + days + "; unique order=" + Convert.ToString(Dts.Variables["User::OrderBy"].Value, CultureInfo.InvariantCulture), "", 0, ref again);
            });
        }
