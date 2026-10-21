        public void Main()
        {
            int limit=Convert.ToInt32(Dts.Variables["$Package::MaxRecordsPerCsv"].Value);
            if(limit<=0) throw new ArgumentException("MaxRecordsPerCsv must be positive.");
            string from=Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff",CultureInfo.InvariantCulture);
            string to=Convert.ToDateTime(Dts.Variables["User::CurrentDateTo"].Value).ToString("yyyy-MM-ddTHH:mm:ss.fffffff",CultureInfo.InvariantCulture);
            string column=Convert.ToString(Dts.Variables["User::ColumnDate"].Value);
            // Typed, invariant literals avoid parameterized Full result set adapter issues in SSDT.
            Dts.Variables["User::SQLStatement"].Value="SELECT TOP ("+limit.ToString(CultureInfo.InvariantCulture)+") * FROM "+
                Convert.ToString(Dts.Variables["User::TableName"].Value)+" WHERE "+column+" >= CONVERT(datetime2(7),N'"+from+"',126) AND "+
                column+" < CONVERT(datetime2(7),N'"+to+"',126);";
            Dts.TaskResult=(int)DTSExecResult.Success;
        }
