        private void Progress(string state, string step, string detail)
        {
            string file = Convert.ToString(Dts.Variables["User::RunLogFile"].Value);
            WriteProgress(file, state, step, detail);
        }

        private void WriteProgress(string file, string state, string step, string detail)
        {
            if (string.IsNullOrEmpty(file)) return;
            try
            {
                // Every compiled Script Task uses the same mutex for this run.
                // Readers never acquire it and can keep their own file handle open.
                using (var hash = System.Security.Cryptography.SHA256.Create())
                using (var mutex = new System.Threading.Mutex(false, "Local\\ArchiveLog_" +
                    BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(file))).Replace("-", "")))
                {
                    bool acquired = false;
                    try
                    {
                        try { acquired = mutex.WaitOne(5000); }
                        catch (System.Threading.AbandonedMutexException) { acquired = true; }
                        if (!acquired) throw new IOException("Timed out waiting for the run log writer.");
                        using (var stream = new FileStream(file, FileMode.Append, FileAccess.Write,
                            FileShare.ReadWrite | FileShare.Delete))
                        using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                        {
                            writer.WriteLine(DateTimeOffset.Now.ToString("o", CultureInfo.InvariantCulture) + " | " +
                                state + " | " + OneLine(step) + " | " + OneLine(detail));
                        }
                    }
                    finally { if (acquired) mutex.ReleaseMutex(); }
                }
            }
            catch (Exception error)
            {
                // An unavailable log must not turn a committed delete into a failed archive job.
                Dts.Events.FireWarning(0, "Archive progress log", error.Message, "", 0);
            }
        }

        private static string OneLine(string value)
        {
            return (value ?? "").Replace("\r", "\\r").Replace("\n", "\\n");
        }
