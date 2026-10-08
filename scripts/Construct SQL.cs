        public void Main()
        {
            Run(delegate {
                // #ArchiveDay is a stable, server-side copy. No source rows are deleted.
                Set("SQLStatement", "SELECT * FROM #ArchiveDay WHERE " + S("QuotedColumn") +
                    " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo ORDER BY " + S("OrderBy") +
                    " OFFSET @Offset ROWS FETCH NEXT @BatchSize ROWS ONLY;");
            });
        }
