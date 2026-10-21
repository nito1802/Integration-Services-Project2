        public void Main()
        {
            var timer = Stopwatch.StartNew();
            string outputFile = Convert.ToString(Dts.Variables["User::OutputFile"].Value, CultureInfo.InvariantCulture);
            long rows = 0;
            var batchKeys = new DataTable();
            var data = ((DataSet)Dts.Variables["User::BatchData"].Value).Tables[0];
            if (data.Rows.Count > 0) {
                outputFile = Path.Combine(Convert.ToString(Dts.Variables["User::FolderFullPath"].Value),
                    Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy_MM_dd", CultureInfo.InvariantCulture) + "_part" +
                    (Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1).ToString(CultureInfo.InvariantCulture) + ".csv");
                Dts.Variables["User::OutputFile"].Value = outputFile;
            }
            try
            {
                {
                    using (var reader = data.CreateDataReader())
                    {
                        DataTable schema = (DataTable)Dts.Variables["User::TableSchema"].Value;
                        if (reader.FieldCount != schema.Rows.Count) throw new InvalidOperationException("Table columns changed during this export.");
                        for (int i = 0; i < reader.FieldCount; i++)
                            if (reader.GetName(i) != Convert.ToString(schema.Rows[i]["ColumnName"]) || reader.GetFieldType(i) != (Type)schema.Rows[i]["DataType"])
                                throw new InvalidOperationException("Table columns changed during this export.");
                        foreach (string key in Convert.ToString(Dts.Variables["User::KeyColumns"].Value).Split(','))
                        {
                            string name = key.Trim();
                            int ordinal = reader.GetOrdinal(name);
                            DataColumn field = batchKeys.Columns.Add(name, reader.GetFieldType(ordinal));
                            field.ExtendedProperties["SqlType"] = Convert.ToString(schema.Rows[ordinal]["SqlType"]);
                        }
                        if (data.Rows.Count > 0)
                        using (var stream = new FileStream(outputFile, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        using (var writer = new StreamWriter(stream, new UTF8Encoding(true)))
                        {
                            writer.WriteLine(Convert.ToString(Dts.Variables["User::CsvHeader"].Value));
                            while (reader.Read())
                            {
                                for (int i = 0; i < reader.FieldCount; i++)
                                {
                                    if (i > 0) writer.Write(";");
                                    string value = reader.IsDBNull(i) ? "" : Convert.ToString(reader.GetValue(i), CultureInfo.InvariantCulture);
                                    writer.Write("\"" + (value ?? "").Replace("\"", "\"\"") + "\"");
                                }
                                writer.WriteLine();
                                var values = new object[batchKeys.Columns.Count];
                                for (int i = 0; i < values.Length; i++)
                                {
                                    values[i] = reader[batchKeys.Columns[i].ColumnName];
                                    if (values[i] == DBNull.Value) throw new InvalidOperationException("Archive key must not contain NULL.");
                                }
                                batchKeys.Rows.Add(values);
                                rows++;
                            }
                            writer.Flush();
                            stream.Flush(true);
                        }
                    }
                }
                bool again = false;
                Dts.Events.FireInformation(0, "CSV Archive", "Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; day=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-dd") + "; cutoff=" + Convert.ToDateTime(Dts.Variables["User::CutoffDate"].Value).ToString("o") + "; batch=" + (Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1) +
                    "; path=" + outputFile + "; rows=" + rows + "; elapsedMs=" + timer.ElapsedMilliseconds, "", 0, ref again);
                if (rows > 0) Dts.Variables["User::DayHasFiles"].Value = true;
                Dts.Variables["User::BatchHasRows"].Value = rows > 0;
                // The next task may delete these keys only after the CSV has been flushed and closed.
                Dts.Variables["User::BatchKeys"].Value = batchKeys;
                Dts.Variables["User::BatchNumber"].Value = Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1L;
            }
            catch (Exception ex)
            {
                throw new IOException("Export failed. Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; day=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-dd") + "; cutoff=" + Convert.ToDateTime(Dts.Variables["User::CutoffDate"].Value).ToString("yyyy-MM-dd") +
                    "; batch=" + (Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value) + 1) + "; file=" + outputFile + "; rowsWritten=" + rows, ex);
            }

            Dts.TaskResult = (int)DTSExecResult.Success;
        }
