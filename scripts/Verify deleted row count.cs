        public void Main()
        {
            if (Convert.ToInt64(Dts.Variables["User::DeletedRows"].Value) != ((DataTable)Dts.Variables["User::BatchKeys"].Value).Rows.Count)
                throw new InvalidOperationException("Deleted row count differs from the archived batch: deleted=" + Dts.Variables["User::DeletedRows"].Value + "; exported=" + ((DataTable)Dts.Variables["User::BatchKeys"].Value).Rows.Count);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
