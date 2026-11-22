        public void Main()
        {
            string task = Convert.ToString(Dts.Variables["System::TaskName"].Value);
            string arguments = task == "Create daily ZIP"
                ? Convert.ToString(Dts.Variables["User::ZipArguments"].Value)
                : Convert.ToString(Dts.Variables["User::ZipTestArguments"].Value);
            string executable = @"C:\Program Files\7-Zip\7z.exe";
            using (var process = new Process())
            {
                process.StartInfo = new ProcessStartInfo
                {
                    FileName = executable,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                var timer = Stopwatch.StartNew();
                process.Start();
                int processId = process.Id;
                process.StandardInput.Close();
                var output = process.StandardOutput.ReadToEndAsync();
                var error = process.StandardError.ReadToEndAsync();
                bool completed = process.WaitForExit(600000);
                if (!completed)
                {
                    process.Kill();
                    process.WaitForExit();
                }
                Dts.Variables["User::ZipProcessOutput"].Value = output.GetAwaiter().GetResult();
                Dts.Variables["User::ZipProcessError"].Value = error.GetAwaiter().GetResult();
                int exitCode = process.ExitCode;
                if (!completed || exitCode != 0)
                {
                    Dts.Variables["User::JobFailed"].Value = true;
                    Dts.Variables["User::ZipProcessFailed"].Value = true;
                    Dts.Variables["User::JobError"].Value = task +
                        ": executable=" + executable + "; arguments=" + arguments +
                        "; processId=" + processId.ToString(CultureInfo.InvariantCulture) +
                        "; exitCode=" + exitCode.ToString(CultureInfo.InvariantCulture) +
                        "; elapsedMs=" + timer.ElapsedMilliseconds.ToString(CultureInfo.InvariantCulture) +
                        (completed ? "" : "; process exceeded 600-second timeout");
                }
            }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
