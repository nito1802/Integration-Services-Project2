        public void Main()
        {
            Run(delegate {
                DateTime from = Convert.ToDateTime(V("DateFrom")).Date.AddDays(Convert.ToInt32(V("LoopCounter")));
                DateTime to = from.AddDays(1);
                Set("CurrentDateFrom", from);
                Set("CurrentDateTo", to);
                Set("BatchNumber", (long)0);
                Set("DayExportedRows", (long)0);
                // Keep source rows and their order stable until Complete day commits.
                Set("CountSQL", "SET NOCOUNT ON; SET XACT_ABORT ON; SET LOCK_TIMEOUT 30000; " +
                    "SET TRANSACTION ISOLATION LEVEL SERIALIZABLE; " +
                    "BEGIN TRY BEGIN TRANSACTION; " +
                    "SELECT COUNT_BIG(*) AS FileRecordCounter FROM " + S("QuotedTable") + " WHERE " + S("QuotedColumn") +
                    " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo; " +
                    "END TRY BEGIN CATCH IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; " +
                    "SET TRANSACTION ISOLATION LEVEL READ COMMITTED; THROW; END CATCH;");
            });
        }
