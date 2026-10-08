        public void Main()
        {
            Run(delegate {
                DateTime from = Convert.ToDateTime(V("DateFrom")).Date.AddDays(Convert.ToInt32(V("LoopCounter")));
                DateTime to = from.AddDays(1);
                Set("CurrentDateFrom", from);
                Set("CurrentDateTo", to);
                Set("BatchNumber", (long)0);
                Set("CountSQL", "SELECT COUNT_BIG(*) FROM " + S("QuotedTable") + " WHERE " + S("QuotedColumn") +
                    " >= @DateFrom AND " + S("QuotedColumn") + " < @DateTo;");
            });
        }
