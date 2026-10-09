        public void Main()
        {
            Run(delegate {
                DateTime from = Convert.ToDateTime(Dts.Variables["User::DateFrom"].Value).Date.AddDays(Convert.ToInt32(Dts.Variables["User::LoopCounter"].Value));
                DateTime to = from.AddDays(1);
                Dts.Variables["User::CurrentDateFrom"].Value = from;
                Dts.Variables["User::CurrentDateTo"].Value = to;
                Dts.Variables["User::BatchNumber"].Value = (long)0;
                Dts.Variables["User::BatchHasRows"].Value = true;
            });
        }
