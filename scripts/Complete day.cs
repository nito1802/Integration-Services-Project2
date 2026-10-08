        public void Main()
        {
            Run(delegate {
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand("SELECT COUNT_BIG(*) FROM #ArchiveDay;", connection))
                    {
                        long expected = Convert.ToInt64(command.ExecuteScalar());
                        if (expected != Convert.ToInt64(V("DayExportedRows"))) throw new InvalidOperationException("Day export row count mismatch.");
                        Set("TableExpectedRows", checked(Convert.ToInt64(V("TableExpectedRows")) + expected));
                    }
                    using (var command = new SqlCommand("DROP TABLE #ArchiveDay;", connection)) command.ExecuteNonQuery();
                }
                finally { Release(connection); }
            });
        }
