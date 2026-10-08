        public void Main()
        {
            Run(delegate {
                DateTime from = Convert.ToDateTime(V("DateFrom")).Date.AddDays(Convert.ToInt32(V("LoopCounter")));
                DateTime to = from.AddDays(1);
                Set("CurrentDateFrom", from);
                Set("CurrentDateTo", to);
                Set("BatchNumber", (long)0);
                Set("DayExportedRows", (long)0);
                // Create in the retained session, outside the parameterized command's scope.
                // UNION prevents SQL Server from copying the source identity property.
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand("IF OBJECT_ID('tempdb..#ArchiveDay') IS NOT NULL DROP TABLE #ArchiveDay; " +
                        "SELECT TOP (0) * INTO #ArchiveDay FROM " + S("QuotedTable") +
                        " UNION ALL SELECT TOP (0) * FROM " + S("QuotedTable") + ";", connection)) command.ExecuteNonQuery();
                }
                finally { Release(connection); }
                Set("CountSQL", "SET NOCOUNT ON; SET XACT_ABORT ON; SET LOCK_TIMEOUT 30000; " +
                    "BEGIN TRY BEGIN TRANSACTION; " +
                    "INSERT INTO #ArchiveDay SELECT * FROM " + S("QuotedTable") + " WITH (HOLDLOCK) WHERE " + S("QuotedColumn") +
                    " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo; COMMIT TRANSACTION; " +
                    "END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; THROW; END CATCH; " +
                    "SELECT COUNT_BIG(*) AS FileRecordCounter FROM #ArchiveDay;");
            });
        }
