        public void Main()
        {
            string folder = Convert.ToString(Dts.Variables["$Package::LogFolder"].Value);
            if (string.IsNullOrWhiteSpace(folder) || !Path.IsPathRooted(folder))
                throw new ArgumentException("LogFolder must be an absolute directory path.");
            folder = Path.GetFullPath(folder);
            Directory.CreateDirectory(folder);
            Dts.Variables["User::RunStartedTicks"].Value = Stopwatch.GetTimestamp();
            string prefix = Path.Combine(folder, "archive_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") +
                "_" + Guid.NewGuid().ToString("N"));
            string file = prefix + "_details.txt";
            string summary = prefix + "_summary.txt";
            using (var stream = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete)) { }
            using (var stream = new FileStream(summary, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete)) { }
            Dts.Variables["User::RunLogFile"].Value = file;
            Dts.Variables["User::RunSummaryFile"].Value = summary;
            Progress("RUN START", "Package", "machine=" + Environment.MachineName);
            Summary("RUN START", "Package", "machine=" + Environment.MachineName + "; details=" + file);
            bool again = false;
            Dts.Events.FireInformation(0, "Archive progress log", "Run log: " + file, "", 0, ref again);
            Dts.Events.FireInformation(0, "Archive progress log", "Run summary: " + summary, "", 0, ref again);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
