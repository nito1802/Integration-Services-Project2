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
            SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
            try
            {
                using (var command = new SqlCommand("SELECT TOP (0) * FROM " + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + ";", connection))
                using (var reader = command.ExecuteReader())
                {
                    var fields = new string[reader.FieldCount];
                    for (int i = 0; i < fields.Length; i++)
                    {
                        string field = reader.GetName(i) + " (" + reader.GetDataTypeName(i) + ")";
                        fields[i] = "\"" + field.Replace("\"", "\"\"") + "\"";
                    }
                    string header = string.Join(";", fields);
                    Dts.Variables["User::CsvHeader"].Value = header;

                }
            }
            finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            Dts.Variables["User::CurrentDateTo"].Value = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).Date.AddDays(1);
            Dts.Variables["User::BatchNumber"].Value = 0L;
            Dts.Variables["User::BatchHasRows"].Value = true;
            Dts.Variables["User::DayHasFiles"].Value = false;
            Dts.Variables["User::ZipFile"].Value = zip;
            Dts.Variables["User::ZipArguments"].Value = "a -tzip -y \"" + zip + "\" \"" + Path.Combine(folder, "*.csv") + "\"";
            Dts.Variables["User::ZipTestArguments"].Value = "t -tzip \"" + zip + "\"";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
