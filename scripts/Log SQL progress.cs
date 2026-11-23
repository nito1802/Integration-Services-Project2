        public void Main()
        {
            Progress("__SQL_STATE__", Convert.ToString(Dts.Variables["System::SourceName"].Value), __SQL_DETAIL__);
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
