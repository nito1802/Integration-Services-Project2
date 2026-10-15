        public void Main()
        {
            var keys = (DataTable)Dts.Variables["User::BatchKeys"].Value;
            SqlConnection connection = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
            try
            {
                using (var copy = new SqlBulkCopy(connection, SqlBulkCopyOptions.KeepIdentity, null))
                {
                    copy.DestinationTableName = "#ArchiveBatchKeys";
                    copy.BulkCopyTimeout = 300;
                    foreach (DataColumn column in keys.Columns) copy.ColumnMappings.Add(column.ColumnName, column.ColumnName);
                    copy.WriteToServer(keys);
                }
            }
            finally { Dts.Connections["ArchiveDb"].ReleaseConnection(connection); }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
