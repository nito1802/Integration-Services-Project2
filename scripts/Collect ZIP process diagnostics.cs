        public void Main()
        {
            // Execute Process has returned and released its output variable locks.
            if (Convert.ToBoolean(Dts.Variables["User::ZipProcessFailed"].Value))
            {
                Dts.Variables["User::JobError"].Value =
                    Convert.ToString(Dts.Variables["User::JobError"].Value) +
                    Environment.NewLine + "7-Zip stdout: " + Convert.ToString(Dts.Variables["User::ZipProcessOutput"].Value) +
                    Environment.NewLine + "7-Zip stderr: " + Convert.ToString(Dts.Variables["User::ZipProcessError"].Value);
                Dts.Variables["User::ZipProcessFailed"].Value = false;
            }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
