        public void Main()
        {
            long expected = Convert.ToInt64(Dts.Variables["User::DayRows"].Value);
            long exported = Convert.ToInt64(Dts.Variables["User::DayExportedRows"].Value);
            if(exported != expected) throw new InvalidOperationException("CSV row count differs from staged day: expected=" + expected + "; exported=" + exported);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
