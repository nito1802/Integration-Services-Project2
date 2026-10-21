        public void Main()
        {
            string day = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy_MM_dd", CultureInfo.InvariantCulture);
            var safeName = new StringBuilder();
            foreach (char c in Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture))
                if (c == '~' || Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0)
                    safeName.Append("~" + ((int)c).ToString("X4", CultureInfo.InvariantCulture));
                else safeName.Append(c);
            string folder = Path.Combine(Path.GetFullPath(Convert.ToString(Dts.Variables["User::ArchiwumPath"].Value, CultureInfo.InvariantCulture)), safeName.ToString(), Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy"), day);
            string zip = folder + ".zip";
            if (Directory.Exists(folder) || File.Exists(folder) || File.Exists(zip) || Directory.Exists(zip))
                throw new IOException("Archive destination already exists. Existing files must be reviewed before retrying. Folder=" + folder + "; ZIP=" + zip);
            Directory.CreateDirectory(folder);
            string output = Path.Combine(folder, safeName + "_" + day + ".csv");
            Dts.Variables["User::FolderFullPath"].Value = folder;
            Dts.Variables["User::OutputFile"].Value = output;
            Dts.Variables["User::CurrentDateTo"].Value = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).Date.AddDays(1);
            Dts.Variables["User::BatchNumber"].Value = 0L;
            Dts.Variables["User::BatchHasRows"].Value = true;
            Dts.Variables["User::DayHasFiles"].Value = false;
            Dts.Variables["User::ZipFile"].Value = zip;
            Dts.Variables["User::ZipArguments"].Value = "a -tzip -y \"" + zip + "\" \"" + Path.Combine(folder, "*.csv") + "\"";
            Dts.Variables["User::ZipTestArguments"].Value = "t -tzip \"" + zip + "\"";
            Dts.Variables["User::DayRows"].Value = 0L;
            Dts.Variables["User::DayExportedRows"].Value = 0L;
            string table = Convert.ToString(Dts.Variables["User::QualifiedTableName"].Value);
            string column = Convert.ToString(Dts.Variables["User::ColumnDate"].Value);
            string from = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff",CultureInfo.InvariantCulture);
            string to = Convert.ToDateTime(Dts.Variables["User::CurrentDateTo"].Value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff",CultureInfo.InvariantCulture);
            Dts.Variables["User::StageDaySql"].Value = "SET NOCOUNT ON; IF OBJECT_ID('tempdb..#ArchiveDay') IS NOT NULL DROP TABLE #ArchiveDay; " +
                "SELECT * INTO #ArchiveDay FROM " + table + " WHERE " + column + " >= CONVERT(datetime2(7),N'" + from + "',126) AND " +
                column + " < CONVERT(datetime2(7),N'" + to + "',126); SELECT COUNT_BIG(*) AS DayRows FROM #ArchiveDay;";
            var matches = new List<string>();
            var nullKeys = new List<string>();
            foreach(string key in Convert.ToString(Dts.Variables["User::KeyColumns"].Value).Split(',')) {
                string name = "[" + key.Trim().Replace("]","]]") + "]";
                matches.Add("s." + name + "=d." + name);
                nullKeys.Add(name + " IS NULL");
            }
            Dts.Variables["User::StageDaySql"].Value = Convert.ToString(Dts.Variables["User::StageDaySql"].Value).Replace(
                "SELECT COUNT_BIG(*) AS DayRows", "IF EXISTS(SELECT 1 FROM #ArchiveDay WHERE " + string.Join(" OR ",nullKeys.ToArray()) +
                ") THROW 50004,'Archive key must not contain NULL.',1; SELECT COUNT_BIG(*) AS DayRows");
            Dts.Variables["User::DeleteSql"].Value = "SET NOCOUNT ON; DELETE s FROM " + table +
                " s INNER JOIN #ArchiveDay d ON " + string.Join(" AND ",matches.ToArray()) + "; SELECT CONVERT(bigint,@@ROWCOUNT) AS DeletedRows;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
