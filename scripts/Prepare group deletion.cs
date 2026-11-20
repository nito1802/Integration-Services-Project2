        public void Main()
        {
            Dts.Variables["User::TableName"].Value = Convert.ToString(Dts.Variables["User::ParentTableName"].Value);
            Dts.Variables["User::QualifiedTableName"].Value = Convert.ToString(Dts.Variables["User::ParentQualifiedTable"].Value);
            Dts.Variables["User::DeleteSql"].Value =
                "SET NOCOUNT ON; SET XACT_ABORT ON; BEGIN TRY BEGIN TRANSACTION; " +
                Convert.ToString(Dts.Variables["User::GroupDeleteSql"].Value) +
                " COMMIT TRANSACTION; END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; THROW; END CATCH; " +
                Convert.ToString(Dts.Variables["User::GroupDropSql"].Value) +
                " DROP TABLE #ArchiveParents; SELECT CONVERT(bigint," +
                Convert.ToInt64(Dts.Variables["User::GroupExpectedRows"].Value).ToString(CultureInfo.InvariantCulture) +
                ") AS DeletedRows;";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
