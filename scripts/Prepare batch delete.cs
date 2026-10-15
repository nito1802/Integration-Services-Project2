        public void Main()
        {
            Run(delegate {
                var keys = (DataTable)Dts.Variables["User::BatchKeys"].Value;
                string table = Convert.ToString(Dts.Variables["User::TableName"].Value);
                var select = new List<string>();
                var match = new List<string>();
                foreach (DataColumn column in keys.Columns)
                {
                    string name = "[" + column.ColumnName.Replace("]", "]]") + "]";
                    select.Add("s." + name);
                    match.Add("s." + name + "=k." + name);
                }
                // A join prevents SELECT INTO from copying the source identity property.
                Dts.Variables["User::PrepareKeysSql"].Value =
                    "IF OBJECT_ID('tempdb..#ArchiveBatchKeys') IS NOT NULL DROP TABLE #ArchiveBatchKeys; " +
                    "SELECT TOP (0) " + string.Join(",", select.ToArray()) + " INTO #ArchiveBatchKeys FROM " + table + " s CROSS JOIN (SELECT 1 AS n) x;";
                Dts.Variables["User::DeleteSql"].Value =
                    "SET NOCOUNT ON; DELETE s FROM " + table + " s INNER JOIN #ArchiveBatchKeys k ON " + string.Join(" AND ", match.ToArray()) +
                    "; SELECT CONVERT(bigint,@@ROWCOUNT) AS DeletedRows;";
            });
        }
