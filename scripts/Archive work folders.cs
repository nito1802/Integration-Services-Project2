        private static bool WorkFolderName(string name, string day)
        {
            if (name == day) return true;
            int part;
            if (name.StartsWith(day + "__PART", StringComparison.Ordinal) &&
                int.TryParse(name.Substring(day.Length + 6), out part) && part >= 2) return true;
            Guid oldAttempt;
            return name.StartsWith(day + "_retry_", StringComparison.Ordinal) &&
                Guid.TryParseExact(name.Substring(day.Length + 7), "N", out oldAttempt);
        }

        private static void CleanWorkFolder(string folder)
        {
            if (!Directory.Exists(folder)) return;
            if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Archive cleanup cannot follow a directory link: " + folder);
            // Never recurse, and never remove archives or unrelated files.
            if (Directory.GetDirectories(folder).Length > 0)
                throw new IOException("Unexpected subdirectory in archive work folder: " + folder);
            string[] files = Directory.GetFiles(folder);
            foreach (string file in files)
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0 ||
                    (!string.Equals(Path.GetExtension(file), ".csv", StringComparison.OrdinalIgnoreCase) &&
                     Path.GetFileName(file) != "archive.pending"))
                    throw new IOException("Preserving unexpected file in archive work folder: " + file);
            foreach (string file in files) File.Delete(file);
            Directory.Delete(folder, false);
        }
