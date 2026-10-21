        public void Main()
        {
            int failed = Convert.ToInt32(Dts.Variables["User::FailedJobs"].Value);
            if (failed > 0)
            {
                Dts.Events.FireError(0, "CSV Archive", "Archive finished with " + failed + " failed job(s). See Archive.ArchiveJobs.ErrorMessage. Successful CSV exports are retained.", "", 0);
                Dts.TaskResult = (int)DTSExecResult.Failure;
            }
            else
            {
                bool again = false;
                Dts.Events.FireInformation(0, "CSV Archive", "All archive jobs completed successfully.", "", 0, ref again);
                Dts.TaskResult = (int)DTSExecResult.Success;
            }
        }
