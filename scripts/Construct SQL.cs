        public void Main()
        {
            Run(delegate {
                // Read each batch directly from the source for the current date range.
                Dts.Variables["User::SQLStatement"].Value = "SELECT * FROM " + Convert.ToString(Dts.Variables["User::QuotedTable"].Value, CultureInfo.InvariantCulture) + " WHERE " + Convert.ToString(Dts.Variables["User::QuotedColumn"].Value, CultureInfo.InvariantCulture) +
                    " >= @DateFrom AND " + Convert.ToString(Dts.Variables["User::QuotedColumn"].Value, CultureInfo.InvariantCulture) + " < @DateTo ORDER BY " + Convert.ToString(Dts.Variables["User::OrderBy"].Value, CultureInfo.InvariantCulture) +
                    " OFFSET @Offset ROWS FETCH NEXT @BatchSize ROWS ONLY;";
            });
        }
