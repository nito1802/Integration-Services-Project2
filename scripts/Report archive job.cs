        public void Main()
        {
            Dts.Variables["User::JobActive"].Value = false;
            Run(delegate {
                bool failed = Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value);
                if (failed) Dts.Variables["User::FailedJobs"].Value = Convert.ToInt32(Dts.Variables["User::FailedJobs"].Value) + 1;
                bool again = false;
                Dts.Events.FireInformation(0, "CSV Archive", "Table=" + Convert.ToString(Dts.Variables["User::TableName"].Value) + "; status=" + (failed ? "Error" : "Success") + "; path=" + Convert.ToString(Dts.Variables["User::OutputFile"].Value), "", 0, ref again);
            });
        }
