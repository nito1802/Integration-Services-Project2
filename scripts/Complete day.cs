        public void Main()
        {
            Run(delegate {
                string folder = S("FolderFullPath");
                string marker = Path.Combine(folder, "_SUCCESS.txt");
                using (var stream = new FileStream(marker + ".tmp", FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(true)))
                {
                    writer.WriteLine("Table=" + S("TableName"));
                    writer.WriteLine("From=" + Convert.ToDateTime(V("CurrentDateFrom")).ToString("o"));
                    writer.WriteLine("To=" + Convert.ToDateTime(V("CurrentDateTo")).ToString("o"));
                    writer.WriteLine("Rows=" + Convert.ToInt64(V("DayExportedRows")));
                    writer.WriteLine("Batches=" + Convert.ToInt64(V("BatchNumber")));
                    writer.Flush(); stream.Flush(true);
                }
                File.Move(marker + ".tmp", marker);
                SqlConnection connection = Acquire();
                try { using (var command = new SqlCommand("DROP TABLE #ArchiveDay;", connection)) command.ExecuteNonQuery(); }
                finally { Release(connection); }
            });
        }
