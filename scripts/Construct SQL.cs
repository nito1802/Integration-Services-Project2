        public void Main()
        {
            Run(delegate {
                // Read each batch directly from the source for the current date range.
                Set("SQLStatement", "SELECT * FROM " + S("QuotedTable") + " WHERE " + S("QuotedColumn") +
                    " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo ORDER BY " + S("OrderBy") +
                    " OFFSET @Offset ROWS FETCH NEXT @BatchSize ROWS ONLY;");
            });
        }
