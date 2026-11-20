        private static string Quote(string name)
        {
            return "[" + name.Replace("]", "]]") + "]";
        }

        public void Main()
        {
            int index = Convert.ToInt32(Dts.Variables["User::MemberIndex"].Value);
            string database = Quote(Convert.ToString(Dts.Variables["User::DatabaseName"].Value));
            string table;
            string source;
            if (index == 0)
            {
                table = Convert.ToString(Dts.Variables["User::ParentQualifiedTable"].Value);
                Dts.Variables["User::TableName"].Value = Convert.ToString(Dts.Variables["User::ParentTableName"].Value);
                source = "SELECT * FROM #ArchiveParents";
            }
            else
            {
                string schema = Convert.ToString(Dts.Variables["User::MemberSchema"].Value);
                string name = Convert.ToString(Dts.Variables["User::MemberTable"].Value);
                table = database + "." + Quote(schema) + "." + Quote(name);
                Dts.Variables["User::TableName"].Value = schema + "." + name;
                source = Convert.ToString(Dts.Variables["User::MemberPlanSource"].Value);
            }
            Dts.Variables["User::QualifiedTableName"].Value = table;
            Dts.Variables["User::MemberSourceSql"].Value = source;
            Dts.Variables["User::ShapeSql"].Value = "SELECT TOP(0) * FROM " + table + ";";
            Dts.Variables["User::MetadataSql"].Value =
                "SELECT name AS ColumnName,system_type_name AS SqlType,is_part_of_unique_key AS IsKey " +
                "FROM sys.dm_exec_describe_first_result_set(N'SELECT * FROM " + table.Replace("'", "''") +
                "',NULL,1) WHERE is_hidden=0 ORDER BY column_ordinal;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
