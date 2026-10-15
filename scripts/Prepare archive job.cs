        public void Main()
        {
            Dts.Variables["User::JobActive"].Value = true;
            Dts.Variables["User::JobFailed"].Value = false;
            Dts.Variables["User::JobError"].Value = "";
            Dts.Variables["User::OutputFile"].Value = "";
            Dts.Variables["User::ArchiwumPath"].Value = Convert.ToString(Dts.Variables["$Package::ArchiveRoot"].Value);
            SqlConnection source = (SqlConnection)Dts.Connections["ArchiveDb"].AcquireConnection(Dts.Transaction);
            try { source.ChangeDatabase(Convert.ToString(Dts.Variables["User::DatabaseName"].Value, CultureInfo.InvariantCulture)); }
            finally { Dts.Connections["ArchiveDb"].ReleaseConnection(source); }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
