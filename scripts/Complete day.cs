        public void Main()
        {
            Run(delegate {
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand("SELECT COUNT_BIG(*) FROM " + S("QuotedTable") +
                        " WHERE " + S("QuotedColumn") + " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo;", connection))
                    {
                        command.CommandTimeout = 300;
                        DateParameters(command, Convert.ToDateTime(V("CurrentDateFrom")), Convert.ToDateTime(V("CurrentDateTo")));
                        long expected = Convert.ToInt64(command.ExecuteScalar());
                        if (expected != Convert.ToInt64(V("DayExportedRows"))) throw new InvalidOperationException("Day export row count mismatch.");
                        Set("TableExpectedRows", checked(Convert.ToInt64(V("TableExpectedRows")) + expected));
                    }
                    using (var command = new SqlCommand("COMMIT TRANSACTION; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;", connection)) command.ExecuteNonQuery();
                }
                finally
                {
                    try
                    {
                        using (var command = new SqlCommand("IF @@TRANCOUNT>0 ROLLBACK TRANSACTION; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;", connection)) command.ExecuteNonQuery();
                    }
                    finally { Release(connection); }
                }
            });
        }
