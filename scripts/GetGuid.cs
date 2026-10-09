        public void Main()
        {
            Run(delegate {
                string day = Convert.ToDateTime(Dts.Variables["System::StartTime"].Value).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                string guid = Guid.NewGuid().ToString();
                var safeName = new StringBuilder();
                foreach (char c in Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture))
                    if (c == '~' || Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0)
                        safeName.Append("~" + ((int)c).ToString("X4", CultureInfo.InvariantCulture));
                    else safeName.Append(c);
                string folder = Path.Combine(Path.GetFullPath(Convert.ToString(Dts.Variables["User::ArchiwumPath"].Value, CultureInfo.InvariantCulture)), day);
                Directory.CreateDirectory(folder);
                string output = Path.Combine(folder, safeName + "_" + day + "_" + guid + ".csv");
                Dts.Variables["User::FolderFullPath"].Value = folder;
                Dts.Variables["User::AddNumber"].Value = guid;
                Dts.Variables["User::OutputFile"].Value = output;
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand("SELECT TOP (0) * FROM " + Convert.ToString(Dts.Variables["User::QuotedTable"].Value, CultureInfo.InvariantCulture) + ";", connection))
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
                        using (var stream = new FileStream(output, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        using (var writer = new StreamWriter(stream, new UTF8Encoding(true)))
                        {
                            writer.WriteLine(header);
                            writer.Flush(); stream.Flush(true);
                        }
                    }
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            });
        }
