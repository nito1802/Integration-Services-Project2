        public void Main()
        {
            Run(delegate {
                string day = Convert.ToDateTime(Dts.Variables["System::StartTime"].Value).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                string guid = Guid.NewGuid().ToString();
                var safeName = new StringBuilder();
                foreach (char c in S("TableName"))
                    if (c == '~' || Array.IndexOf(Path.GetInvalidFileNameChars(), c) >= 0)
                        safeName.Append("~" + ((int)c).ToString("X4", CultureInfo.InvariantCulture));
                    else safeName.Append(c);
                string folder = Path.Combine(Path.GetFullPath(S("ArchiwumPath")), day);
                Directory.CreateDirectory(folder);
                string output = Path.Combine(folder, safeName + "_" + day + "_" + guid + ".csv");
                Set("FolderFullPath", folder);
                Set("AddNumber", guid);
                Set("OutputFile", output);
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand("SELECT TOP (0) * FROM " + S("QuotedTable") + ";", connection))
                    using (var reader = command.ExecuteReader())
                    {
                        string header = CsvHeader(reader);
                        Set("CsvHeader", header);
                        using (var stream = new FileStream(output, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        using (var writer = new StreamWriter(stream, new UTF8Encoding(true)))
                        {
                            writer.WriteLine(header);
                            writer.Flush(); stream.Flush(true);
                        }
                    }
                }
                finally { Release(connection); }
            });
        }
