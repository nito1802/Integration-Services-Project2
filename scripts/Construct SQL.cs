        public void Main()
        {
            Dts.Variables["User::SQLStatement"].Value = "SELECT TOP (1000) * FROM " + Convert.ToString(Dts.Variables["User::TableName"].Value) +
                " WHERE " + Convert.ToString(Dts.Variables["User::ColumnDate"].Value) + " < @Cutoff;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
