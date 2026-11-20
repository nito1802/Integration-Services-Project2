        private static string ArchivePathName(string name)
        {
            var safeName = new StringBuilder();
            foreach (char c in name)
                if (c == '~' || Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0)
                    safeName.Append("~" + ((int)c).ToString("X4", CultureInfo.InvariantCulture));
                else safeName.Append(c);
            return safeName.ToString();
        }

        public void Main()
        {
            DateTime date = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value);
            string day = date.ToString("yyyy_MM_dd", CultureInfo.InvariantCulture);
            string[] months = { "styczen", "luty", "marzec", "kwiecien", "maj", "czerwiec",
                "lipiec", "sierpien", "wrzesien", "pazdziernik", "listopad", "grudzien" };
            string safeName = ArchivePathName(Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture));
            string database = ArchivePathName(Convert.ToString(Dts.Variables["User::DatabaseName"].Value, CultureInfo.InvariantCulture));
            string folder = Path.Combine(Path.GetFullPath(Convert.ToString(Dts.Variables["User::ArchiwumPath"].Value, CultureInfo.InvariantCulture)), database,
                safeName, date.ToString("yyyy", CultureInfo.InvariantCulture), months[date.Month - 1], day);
            string zip = folder + ".zip";
            if (Directory.Exists(folder) || File.Exists(folder) || File.Exists(zip) || Directory.Exists(zip))
            {
                folder += "_retry_" + Convert.ToString(Dts.Variables["User::ArchiveAttempt"].Value);
                zip = folder + ".zip";
                if (Directory.Exists(folder) || File.Exists(folder) || File.Exists(zip) || Directory.Exists(zip))
                    throw new IOException("Archive attempt destination already exists: " + folder);
            }
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
            string snapshot = "#ArchiveMember" + Convert.ToInt32(Dts.Variables["User::MemberIndex"].Value).ToString(CultureInfo.InvariantCulture);
            Dts.Variables["User::MemberSnapshot"].Value = snapshot;
            Dts.Variables["User::MemberDropSql"].Value = "IF OBJECT_ID('tempdb.." + snapshot + "') IS NOT NULL DROP TABLE " + snapshot + ";";
            Dts.Variables["User::StageDaySql"].Value = "SET NOCOUNT ON; " +
                Convert.ToString(Dts.Variables["User::MemberSourceSql"].Value).Replace("SELECT * FROM #ArchiveParents", "SELECT * INTO " + snapshot + " FROM #ArchiveParents")
                    .Replace("SELECT c.* FROM ", "SELECT c.* INTO " + snapshot + " FROM ") +
                "; SELECT COUNT_BIG(*) AS DayRows FROM " + snapshot + ";";
            var matches = new List<string>();
            var nullKeys = new List<string>();
            foreach(string key in Convert.ToString(Dts.Variables["User::KeyColumns"].Value).Split(',')) {
                string name = "[" + key.Trim().Replace("]","]]") + "]";
                matches.Add("s." + name + "=d." + name);
                nullKeys.Add(name + " IS NULL");
            }
            Dts.Variables["User::StageDaySql"].Value = Convert.ToString(Dts.Variables["User::StageDaySql"].Value).Replace(
                "SELECT COUNT_BIG(*) AS DayRows", "IF EXISTS(SELECT 1 FROM " + snapshot + " WHERE " + string.Join(" OR ",nullKeys.ToArray()) +
                ") THROW 50004,'Archive key must not contain NULL.',1; SELECT COUNT_BIG(*) AS DayRows");
            Dts.Variables["User::DeleteSql"].Value = "SET NOCOUNT ON; DELETE s FROM " + table +
                " s INNER JOIN " + snapshot + " d ON " + string.Join(" AND ",matches.ToArray()) + ";";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
