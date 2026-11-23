        public void Main()
        {
            Dts.Variables["User::RunLogFile"].Value = "";
            Dts.Variables["User::RunSummaryFile"].Value = "";
            bool detailsEnabled = Convert.ToBoolean(Dts.Variables["$Package::DetailsLog"].Value);
            bool summaryEnabled = Convert.ToBoolean(Dts.Variables["$Package::Summarylog"].Value);
            if (!detailsEnabled && !summaryEnabled)
            {
                Dts.TaskResult = (int)DTSExecResult.Success;
                return;
            }
            string folder = Convert.ToString(Dts.Variables["$Package::LogPath"].Value);
            if (string.IsNullOrWhiteSpace(folder) || !Path.IsPathRooted(folder))
                throw new ArgumentException("LogPath must be an absolute directory path.");
            folder = Path.GetFullPath(folder);
            Directory.CreateDirectory(folder);
            Dts.Variables["User::RunStartedTicks"].Value = Stopwatch.GetTimestamp();
            string prefix = Path.Combine(folder, "archive_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") +
                "_" + Guid.NewGuid().ToString("N"));
            string file = detailsEnabled ? prefix + "_details.txt" : "";
            string summary = summaryEnabled ? prefix + "_summary.txt" : "";
            if (detailsEnabled)
                using (var stream = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete)) { }
            if (summaryEnabled)
                using (var stream = new FileStream(summary, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete)) { }
            Dts.Variables["User::RunLogFile"].Value = file;
            Dts.Variables["User::RunSummaryFile"].Value = summary;
            Progress("RUN START", "Package", "machine=" + Environment.MachineName);
            Summary("RUN START", "Package", "machine=" + Environment.MachineName + "; details=" + file);
            bool again = false;
            if (detailsEnabled) Dts.Events.FireInformation(0, "Archive progress log", "Run log: " + file, "", 0, ref again);
            if (summaryEnabled) Dts.Events.FireInformation(0, "Archive progress log", "Run summary: " + summary, "", 0, ref again);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
