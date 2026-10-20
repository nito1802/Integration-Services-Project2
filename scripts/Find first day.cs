        public void Main()
        {
            if (Convert.ToInt32(Dts.Variables["$Package::MaxRecordsPerCsv"].Value) <= 0)
                throw new ArgumentException("MaxRecordsPerCsv must be positive.");
            if (!File.Exists(Convert.ToString(Dts.Variables["$Package::SevenZipPath"].Value)))
                throw new FileNotFoundException("SevenZipPath does not exist.");
            var connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
            try {
                using (var command = new SqlCommand("SELECT MIN(" + Convert.ToString(Dts.Variables["User::ColumnDate"].Value) + ") FROM " + Convert.ToString(Dts.Variables["User::TableName"].Value) + " WHERE " + Convert.ToString(Dts.Variables["User::ColumnDate"].Value) + " < @Cutoff", connection)) {
                    command.CommandTimeout = 300;
                    command.Parameters.Add("@Cutoff", SqlDbType.DateTime2).Value = Dts.Variables["User::CutoffDate"].Value;
                    object first = command.ExecuteScalar();
                    Dts.Variables["User::CurrentDateFrom"].Value = first == DBNull.Value || first == null ? Convert.ToDateTime(Dts.Variables["User::CutoffDate"].Value) : Convert.ToDateTime(first).Date;
                }
            } finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
