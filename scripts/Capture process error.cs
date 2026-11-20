        public void Main()
        {
            Dts.Variables["User::JobFailed"].Value = true;
            Dts.Variables["User::JobError"].Value =
                Convert.ToString(Dts.Variables["System::ErrorDescription"].Value) +
                Environment.NewLine + "7-Zip stdout: " + Convert.ToString(Dts.Variables["User::ZipProcessOutput"].Value) +
                Environment.NewLine + "7-Zip stderr: " + Convert.ToString(Dts.Variables["User::ZipProcessError"].Value);
            Dts.Variables["System::Propagate"].Value = false;
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
