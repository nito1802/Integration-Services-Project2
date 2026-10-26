        public void Main()
        {
            if (Convert.ToInt32(Dts.Variables["User::Days"].Value) <= 0) throw new ArgumentException("Days must be positive.");
            if (Convert.ToInt32(Dts.Variables["$Package::MaxRecordsPerCsv"].Value) <= 0) throw new ArgumentException("MaxRecordsPerCsv must be positive.");
            string database = Convert.ToString(Dts.Variables["User::DatabaseName"].Value);
            if(string.IsNullOrWhiteSpace(database)) throw new ArgumentException("DatabaseName is required.");
            string table = "[" + database.Replace("]","]]") + "]." + Convert.ToString(Dts.Variables["User::TableName"].Value);
            Dts.Variables["User::QualifiedTableName"].Value = table;
            string column = Convert.ToString(Dts.Variables["User::ColumnDate"].Value);
            Dts.Variables["User::ShapeSql"].Value = "SELECT TOP (0) * FROM " + table + ";";
            Dts.Variables["User::FirstDaySql"].Value = "SELECT CONVERT(datetime2(7),COALESCE(CONVERT(date,MIN(" + column + ")),@Cutoff)) FROM " + table + " WHERE " + column + " < @Cutoff;";
            Dts.Variables["User::MetadataSql"].Value =
                "SELECT name AS ColumnName,system_type_name AS SqlType,is_part_of_unique_key AS IsKey " +
                "FROM sys.dm_exec_describe_first_result_set(N'SELECT * FROM " + table.Replace("'","''") + "',NULL,1) " +
                "WHERE is_hidden=0 ORDER BY column_ordinal;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
