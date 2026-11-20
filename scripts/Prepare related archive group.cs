        public void Main()
        {
            string table = Convert.ToString(Dts.Variables["User::QualifiedTableName"].Value);
            string column = Convert.ToString(Dts.Variables["User::ColumnDate"].Value);
            Dts.Variables["User::ParentTableName"].Value = Convert.ToString(Dts.Variables["User::TableName"].Value);
            Dts.Variables["User::ParentQualifiedTable"].Value = table;
            Dts.Variables["User::GroupDeleteSql"].Value = "";
            Dts.Variables["User::GroupDropSql"].Value = "";
            Dts.Variables["User::GroupExpectedRows"].Value = 0L;
            Dts.Variables["User::MemberIndex"].Value = 0;
            Dts.Variables["User::ArchiveAttempt"].Value = Guid.NewGuid().ToString("N");
            var archives = new DataTable();
            archives.Columns.Add("Folder", typeof(string));
            archives.Columns.Add("Zip", typeof(string));
            archives.Columns.Add("HasRows", typeof(bool));
            Dts.Variables["User::CompletedArchives"].Value = archives;
            string from = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff", CultureInfo.InvariantCulture);
            string to = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).Date.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss.fffffff", CultureInfo.InvariantCulture);
            Dts.Variables["User::GroupStageSql"].Value =
                "IF OBJECT_ID('tempdb..#ArchiveParents') IS NOT NULL DROP TABLE #ArchiveParents; SELECT * INTO #ArchiveParents FROM " +
                table + " WHERE " + column + " >= CONVERT(datetime2(7),N'" + from + "',126) AND " + column +
                " < CONVERT(datetime2(7),N'" + to + "',126);";
            Dts.Variables["User::NextDaySql"].Value =
                "SELECT CONVERT(datetime2(7),COALESCE(CONVERT(date,MIN(" + column + ")),@Cutoff)) FROM " + table +
                " WHERE " + column + " >= CONVERT(datetime2(7),N'" + to + "',126) AND " + column + " < @Cutoff;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
