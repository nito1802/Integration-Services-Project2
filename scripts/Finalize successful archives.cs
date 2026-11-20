        private static bool IsRetry(string name, string day)
        {
            string prefix = day + "_retry_";
            Guid attempt;
            return name.StartsWith(prefix, StringComparison.Ordinal) &&
                Guid.TryParseExact(name.Substring(prefix.Length), "N", out attempt);
        }

        public void Main()
        {
            string day = Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value)
                .ToString("yyyy_MM_dd", CultureInfo.InvariantCulture);
            var archives = (DataTable)Dts.Variables["User::CompletedArchives"].Value;
            foreach (DataRow archive in archives.Rows)
            {
                if (!Convert.ToBoolean(archive["HasRows"])) continue;
                string zip = Path.GetFullPath(Convert.ToString(archive["Zip"]));
                string directory = Path.GetDirectoryName(zip);
                string canonical = Path.Combine(directory, day + ".zip");
                // Publish the verified archive before removing any previous attempts.
                if (!string.Equals(zip, canonical, StringComparison.OrdinalIgnoreCase))
                {
                    if (File.Exists(canonical)) File.Replace(zip, canonical, null);
                    else File.Move(zip, canonical);
                }
                if (!File.Exists(canonical))
                    throw new IOException("Successful archive is missing: " + canonical);
                foreach (string file in Directory.GetFiles(directory, day + "_retry_*.zip"))
                    if (IsRetry(Path.GetFileNameWithoutExtension(file), day)) File.Delete(file);
                foreach (string folder in Directory.GetDirectories(directory, day + "*"))
                {
                    string name = Path.GetFileName(folder);
                    if (name != day && !IsRetry(name, day)) continue;
                    if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0)
                        throw new IOException("Archive cleanup cannot follow a directory link: " + folder);
                    foreach (string csv in Directory.GetFiles(folder, "*.csv")) File.Delete(csv);
                    Directory.Delete(folder, false);
                }
            }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
