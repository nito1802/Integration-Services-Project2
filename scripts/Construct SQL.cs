        public void Main()
        {
            Dts.Variables["User::SQLStatement"].Value = "SELECT TOP (@Limit) * FROM " + Convert.ToString(Dts.Variables["User::TableName"].Value) +
                " WHERE " + Convert.ToString(Dts.Variables["User::ColumnDate"].Value) + " >= @From AND " + Convert.ToString(Dts.Variables["User::ColumnDate"].Value) + " < @To;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
