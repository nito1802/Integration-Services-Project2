        private void Summary(string state, string step, string detail)
        {
            WriteProgress(Convert.ToString(Dts.Variables["User::RunSummaryFile"].Value), state, step, detail);
        }

        private static string SummaryElapsed(long started)
        {
            double milliseconds = started <= 0 ? 0 :
                (Stopwatch.GetTimestamp() - started) * 1000.0 / Stopwatch.Frequency;
            return "elapsedMs=" + milliseconds.ToString("F1", CultureInfo.InvariantCulture) +
                "; duration=" + TimeSpan.FromMilliseconds(milliseconds).ToString("c", CultureInfo.InvariantCulture);
        }
