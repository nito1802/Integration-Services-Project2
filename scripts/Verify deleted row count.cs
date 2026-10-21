        public void Main()
        {
            long expected = Convert.ToInt64(Dts.Variables["User::DayRows"].Value);
            long deleted = Convert.ToInt64(Dts.Variables["User::DeletedRows"].Value);
            if(deleted != expected) throw new InvalidOperationException("Deleted row count differs from archived day: expected=" + expected + "; deleted=" + deleted);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
