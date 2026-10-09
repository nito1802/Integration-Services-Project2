        public void Main()
        {
            Run(delegate {
                var timer = Stopwatch.StartNew();
                string outputFile = Convert.ToString(Dts.Variables["User::OutputFile"].Value, CultureInfo.InvariantCulture);
                long rows = 0;
                SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
                try
                {
                    using (var command = new SqlCommand(Convert.ToString(Dts.Variables["User::SQLStatement"].Value, CultureInfo.InvariantCulture), connection))
                    {
                        command.CommandTimeout = 300;
                        command.Parameters.Add("@DateFrom", SqlDbType.DateTime2).Value = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value);
                        command.Parameters.Add("@DateTo", SqlDbType.DateTime2).Value = Convert.ToDateTime(Dts.Variables["User::CurrentDateTo"].Value);
                        command.Parameters.Add("@Offset", SqlDbType.BigInt).Value = checked(Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) * 1000L);
                        command.Parameters.Add("@BatchSize", SqlDbType.Int).Value = 1000;
                        using (var reader = command.ExecuteReader())
                        {
                            var fields = new string[reader.FieldCount];
                            for (int i = 0; i < fields.Length; i++)
                            {
                                string field = reader.GetName(i) + " (" + reader.GetDataTypeName(i) + ")";
                                fields[i] = "\"" + field.Replace("\"", "\"\"") + "\"";
                            }
                            if (string.Join(";", fields) != Convert.ToString(Dts.Variables["User::CsvHeader"].Value, CultureInfo.InvariantCulture)) throw new InvalidOperationException("Table columns changed during this export.");
                            using (var stream = new FileStream(outputFile, FileMode.Open, FileAccess.Write, FileShare.None))
                            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                            {
                                stream.Seek(0, SeekOrigin.End);
                                while (reader.Read())
                                {
                                    for (int i = 0; i < reader.FieldCount; i++)
                                    {
                                        if (i > 0) writer.Write(";");
                                        string value = reader.IsDBNull(i) ? "" : Convert.ToString(reader.GetValue(i), CultureInfo.InvariantCulture);
                                        writer.Write("\"" + (value ?? "").Replace("\"", "\"\"") + "\"");
                                    }
                                    writer.WriteLine();
                                    rows++;
                                }
                                writer.Flush();
                                stream.Flush(true);
                                }
                        }
                    }
                    bool again = false;
                    Dts.Events.FireInformation(0, "CSV Archive", "Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; from=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("o") +
                        "; to=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateTo"].Value).ToString("o") + "; batch=" + (Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1) +
                        "; path=" + outputFile + "; rows=" + rows + "; elapsedMs=" + timer.ElapsedMilliseconds, "", 0, ref again);
                    Dts.Variables["User::BatchHasRows"].Value = rows > 0;
                    Dts.Variables["User::BatchNumber"].Value = Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1L;
                }
                catch (Exception ex)
                {
                    throw new IOException("Export failed. Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; day=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-dd") +
                        "; batch=" + (Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1) + "; file=" + outputFile + "; rowsWritten=" + rows, ex);
                }
                finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            });
        }
