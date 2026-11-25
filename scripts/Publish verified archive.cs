        public void Main()
        {
            string pending = Convert.ToString(Dts.Variables["User::ZipWorkingFile"].Value);
            string target = Convert.ToString(Dts.Variables["User::ZipFile"].Value);
            // File.Move without overwrite fails if a destination appeared meanwhile.
            // The database is untouched until every member has been published.
            File.Move(pending, target);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
