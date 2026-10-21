        public void Main()
        {
            int limit = Convert.ToInt32(Dts.Variables["$Package::MaxRecordsPerCsv"].Value);
            long offset = Convert.ToInt64(Dts.Variables["User::DayExportedRows"].Value);
            if(limit <= 0 || offset < 0) throw new ArgumentException("Invalid batch limit or offset.");
            var order = new List<string>();
            foreach(string key in Convert.ToString(Dts.Variables["User::KeyColumns"].Value).Split(','))
                order.Add("[" + key.Trim().Replace("]","]]") + "]");
            Dts.Variables["User::SQLStatement"].Value = "SELECT * FROM #ArchiveDay ORDER BY " + string.Join(",",order.ToArray()) +
                " OFFSET " + offset.ToString(CultureInfo.InvariantCulture) + " ROWS FETCH NEXT " + limit.ToString(CultureInfo.InvariantCulture) + " ROWS ONLY;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
