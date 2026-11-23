        private string ProgressContext()
        {
            if (Convert.ToInt32(Dts.Variables["User::JobNumber"].Value) == 0) return "";
            string context = "job=" + Dts.Variables["User::JobNumber"].Value +
                "; database=" + Convert.ToString(Dts.Variables["User::DatabaseName"].Value).Trim() +
                "; table=" + Convert.ToString(Dts.Variables["User::TableName"].Value).Trim();
            if (Convert.ToInt32(Dts.Variables["User::DayNumber"].Value) > 0)
                context += "; day=" + Convert.ToDateTime(Dts.Variables["User::CurrentDateFrom"].Value).ToString("yyyy-MM-dd") +
                    "; dayNumber=" + Dts.Variables["User::DayNumber"].Value +
                    "; memberIndex=" + Dts.Variables["User::MemberIndex"].Value +
                    "; rows=" + Dts.Variables["User::DayExportedRows"].Value + "/" + Dts.Variables["User::DayRows"].Value;
            return context;
        }
