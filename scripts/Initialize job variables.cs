        public void Main()
        {
            Dts.Variables["User::JobActive"].Value = true;
            Dts.Variables["User::JobFailed"].Value = false;
            Dts.Variables["User::JobError"].Value = "";
            Dts.Variables["User::OutputFile"].Value = "";
            Dts.Variables["User::BatchHasRows"].Value = true;
            Dts.Variables["User::BatchNumber"].Value = (long)0;
            Dts.Variables["User::ArchiwumPath"].Value = Convert.ToString(Dts.Variables["$Package::ArchiveRoot"].Value);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
