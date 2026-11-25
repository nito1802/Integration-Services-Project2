        public void Main()
        {
            var archives = (DataTable)Dts.Variables["User::CompletedArchives"].Value;
            foreach (DataRow archive in archives.Rows)
            {
                if (!Convert.ToBoolean(archive["HasRows"])) continue;
                string zip = Path.GetFullPath(Convert.ToString(archive["Zip"]));
                if (!File.Exists(zip)) throw new IOException("Verified archive is missing: " + zip);
                // Cleanup is restricted to the recorded work folder. No ZIP is
                // renamed, overwritten or deleted, including legacy retry files.
                string folder = Path.GetFullPath(Convert.ToString(archive["Folder"]));
                if (!string.Equals(Path.GetDirectoryName(folder), Path.GetDirectoryName(zip), StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Work folder is outside the archive directory: " + folder);
                CleanWorkFolder(folder);
            }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
