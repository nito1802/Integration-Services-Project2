        public void Main()
        {
            Run(delegate {
                string guid = Guid.NewGuid().ToString();
                Set("AddNumber", guid);
                long batch = Convert.ToInt64(V("BatchNumber")) + 1;
                Set("OutputFile", Path.Combine(S("FolderFullPath"),
                    "part_" + batch.ToString("D3", CultureInfo.InvariantCulture) + "_" + guid + ".csv"));
            });
        }
