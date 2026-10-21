        public void Main()
        {
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
            // KeepIdentity in Stage batch keys preserves source values for inherited IDENTITY columns.
            Dts.Variables["User::PrepareKeysSql"].Value =
                "IF OBJECT_ID('tempdb..#ArchiveBatchKeys') IS NOT NULL DROP TABLE #ArchiveBatchKeys; " +
                "SELECT TOP (0) " + string.Join(",", select.ToArray()) + " INTO #ArchiveBatchKeys FROM " + table + " s;";
            Dts.Variables["User::DeleteSql"].Value =
                "SET NOCOUNT ON; DELETE s FROM " + table + " s INNER JOIN #ArchiveBatchKeys k ON " + string.Join(" AND ", match.ToArray()) +
                "; SELECT CONVERT(bigint,@@ROWCOUNT) AS DeletedRows;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
