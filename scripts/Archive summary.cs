        public void Main()
        {
            int failed = Convert.ToInt32(V("FailedJobs"));
            if (failed > 0)
            {
                Dts.Events.FireError(0, "CSV Archive", "Archive finished with " + failed + " failed job(s). See Archive.ArchiveJobs.ErrorMessage. Successful CSV exports are retained.", "", 0);
                Dts.TaskResult = (int)DTSExecResult.Failure;
            }
            else { Info("All archive jobs completed successfully."); Dts.TaskResult = (int)DTSExecResult.Success; }
        }
