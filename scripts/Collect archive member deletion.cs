        public void Main()
        {
            int index = Convert.ToInt32(Dts.Variables["User::MemberIndex"].Value);
            string snapshot = "#ArchiveMember" + index.ToString(CultureInfo.InvariantCulture);
            long expected = Convert.ToInt64(Dts.Variables["User::DayRows"].Value);
            ((DataTable)Dts.Variables["User::CompletedArchives"].Value).Rows.Add(
                Convert.ToString(Dts.Variables["User::FolderFullPath"].Value),
                Convert.ToString(Dts.Variables["User::ZipFile"].Value), expected > 0);
            string deletion = Convert.ToString(Dts.Variables["User::DeleteSql"].Value);
            Dts.Variables["User::GroupDeleteSql"].Value = deletion +
                " IF @@ROWCOUNT <> " + expected.ToString(CultureInfo.InvariantCulture) +
                " THROW 50005,'Deleted row count differs from archived member.',1; " +
                Convert.ToString(Dts.Variables["User::GroupDeleteSql"].Value);
            Dts.Variables["User::GroupDropSql"].Value =
                Convert.ToString(Dts.Variables["User::GroupDropSql"].Value) + " DROP TABLE " + snapshot + ";";
            Dts.Variables["User::GroupExpectedRows"].Value =
                Convert.ToInt64(Dts.Variables["User::GroupExpectedRows"].Value) + expected;
            Dts.Variables["User::MemberIndex"].Value = index + 1;
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
