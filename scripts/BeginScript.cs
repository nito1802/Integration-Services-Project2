        public void Main()
        {
            Run(delegate {
                string[] parts = TableParts(S("TableName"));
                string table = Quote(parts[0]) + "." + Quote(parts[1]);
                string column = S("ColumnDate");
                string quotedColumn = Quote(column);
                int days = Convert.ToInt32(V("Days"));
                if (days <= 0) throw new ArgumentException("Days must be positive: 90 means full days older than 90 days.");
                SqlConnection connection = Acquire();
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
                        using (var reader = command.ExecuteReader()) while (reader.Read()) keys.Add(Quote(reader.GetString(0)));
                    }
                    if (keys.Count == 0) throw new InvalidOperationException("No unfiltered unique key: " + table);
                    Set("OrderBy", string.Join(", ", keys.ToArray()));
                }
                finally { Release(connection); }
                Set("QuotedTable", table);
                Set("QuotedColumn", quotedColumn);
                Set("BeginScript", "SET NOCOUNT ON; DECLARE @Cutoff date=DATEADD(day,-@Days,CONVERT(date,GETDATE())); " +
                    "DECLARE @First date=(SELECT CONVERT(date,MIN(" + quotedColumn + ")) FROM " + table + " WHERE " + quotedColumn + " < @Cutoff); " +
                    "SELECT CASE WHEN @First IS NULL THEN 0 ELSE DATEDIFF(day,@First,@Cutoff) END AS DaysCounter, " +
                    "COALESCE(@First,@Cutoff) AS DateFrom, @Cutoff AS DateTo;");
                Set("LoopCounter", 0);
                Info("Table=" + table + "; Days=" + days + "; unique order=" + S("OrderBy"));
            });
        }
