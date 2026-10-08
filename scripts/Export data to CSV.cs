        public void Main()
        {
            Run(delegate {
                var timer = Stopwatch.StartNew();
                string outputFile = S("OutputFile");
                string temporaryFile = outputFile + ".tmp";
                long rows = 0;
                long expected = Math.Min(1000L, Convert.ToInt64(V("FileRecordCounter")));
                SqlConnection connection = Acquire();
                try
                {
                    if (File.Exists(outputFile)) throw new IOException("Completed CSV already exists: " + outputFile);
                    using (var command = new SqlCommand(S("SQLStatement"), connection))
                    {
                        command.CommandTimeout = 300;
                        DateParameters(command, Convert.ToDateTime(V("CurrentDateFrom")), Convert.ToDateTime(V("CurrentDateTo")));
                        command.Parameters.Add("@Offset", SqlDbType.BigInt).Value = checked(Convert.ToInt64(V("BatchNumber")) * 1000L);
                        command.Parameters.Add("@BatchSize", SqlDbType.Int).Value = 1000;
                        using (var reader = command.ExecuteReader())
                        {
                            if (CsvHeader(reader) != S("CsvHeader")) throw new InvalidOperationException("Table columns changed during this export.");
                            using (var stream = new FileStream(temporaryFile, FileMode.Open, FileAccess.Write, FileShare.None))
                            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                            {
                            stream.Seek(0, SeekOrigin.End);
                            while (reader.Read())
                            {
                                for (int i = 0; i < reader.FieldCount; i++)
                                {
                                    if (i > 0) writer.Write(";");
                                    string value = reader.IsDBNull(i) ? "" : Convert.ToString(reader.GetValue(i), CultureInfo.InvariantCulture);
                                    writer.Write(EscapeCsv(value));
                                }
                                writer.WriteLine();
                                rows++;
                            }
                            writer.Flush();
                            stream.Flush(true);
                            }
                        }
                    }
                    if (rows != expected) throw new InvalidOperationException("Batch row count mismatch: expected " + expected + ", got " + rows);
                    Set("DayExportedRows", Convert.ToInt64(V("DayExportedRows")) + rows);
                    Set("TableExportedRows", checked(Convert.ToInt64(V("TableExportedRows")) + rows));
                    Info("Table=" + S("TableName") + "; from=" + Convert.ToDateTime(V("CurrentDateFrom")).ToString("o") +
                        "; to=" + Convert.ToDateTime(V("CurrentDateTo")).ToString("o") + "; batch=" + (Convert.ToInt64(V("BatchNumber")) + 1) +
                        "; path=" + outputFile + "; rows=" + rows + "; elapsedMs=" + timer.ElapsedMilliseconds);
                    Set("BatchNumber", Convert.ToInt64(V("BatchNumber")) + 1L);
                }
                catch (Exception ex)
                {
                    try
                    {
                        using (var rollback = new SqlCommand("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;", connection)) rollback.ExecuteNonQuery();
                    }
                    catch (Exception cleanupError) { Info("Transaction cleanup failed: " + cleanupError.Message); }
                    throw new IOException("Export failed. Table=" + S("TableName") + "; day=" + Convert.ToDateTime(V("CurrentDateFrom")).ToString("yyyy-MM-dd") +
                        "; batch=" + (Convert.ToInt64(V("BatchNumber")) + 1) + "; file=" + outputFile + "; rowsWritten=" + rows, ex);
                }
                finally { Release(connection); }
            });
        }
