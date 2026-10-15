        public void Main()
        {
            Dts.Variables["User::JobFailed"].Value = true;
            Dts.Variables["User::JobError"].Value = Convert.ToString(Dts.Variables["System::ErrorDescription"].Value);
            Dts.Variables["System::Propagate"].Value = false;
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
