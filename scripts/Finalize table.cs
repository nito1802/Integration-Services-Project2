        public void Main()
        {
            Run(delegate {
                long rows = Convert.ToInt64(V("TableExportedRows"));
                if (rows != Convert.ToInt64(V("TableExpectedRows"))) throw new InvalidOperationException("Table export row count mismatch.");
                File.Move(S("OutputFile") + ".tmp", S("OutputFile"));
                Info("Completed table=" + S("TableName") + "; rows=" + rows + "; path=" + S("OutputFile"));
            });
        }
