        public void Main()
        {
            // Called only after both Execute Process Tasks succeed.
            string folder = Convert.ToString(Dts.Variables["User::FolderFullPath"].Value);
            if (Directory.Exists(folder)) {
                foreach (string file in Directory.GetFiles(folder, "*.csv")) File.Delete(file);
                Directory.Delete(folder, false);
            }
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
