        public void Main()
        {
            string[] parts = Convert.ToString(Dts.Variables["$Package::ArchiveJobsTable"].Value).Split('.');
            if(parts.Length != 2 && parts.Length != 3) throw new ArgumentException("ArchiveJobsTable must contain schema.table or database.schema.table, for example nito_superDb.Archive.ArchiveJobs.");
            for(int i=0;i<parts.Length;i++) {
                string name=parts[i].Trim();
                if(name.StartsWith("[") && name.EndsWith("]")) name=name.Substring(1,name.Length-2).Replace("]]","]");
                if(string.IsNullOrWhiteSpace(name) || name.Length>128) throw new ArgumentException("Invalid database, schema or table in ArchiveJobsTable.");
                parts[i]="["+name.Replace("]","]]")+"]";
            }
            string table=string.Join(".",parts);
            Dts.Variables["User::JobsSelectSql"].Value="SELECT Id, DatabaseName, TableName, ArchiveOlderThanDays, DateColumn FROM "+table+" ORDER BY Id;";
            Dts.Variables["User::JobStartSql"].Value="UPDATE "+table+" SET ErrorMessage=NULL, LastProcessedAt=SYSDATETIME(), LastProcessedStatus=NULL WHERE Id=@Id; IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;";
            Dts.Variables["User::JobResultSql"].Value="DECLARE @Now datetime2=SYSDATETIME(); UPDATE "+table+
                " SET LastProcessedAt=@Now, LastProcessedStatus=CASE WHEN @Failed=1 THEN N'Error' ELSE N'Success' END,"+
                " ErrorMessage=CASE WHEN @Failed=1 THEN @Error ELSE NULL END,"+
                " LastSuccesProcessedAt=CASE WHEN @Failed=0 THEN @Now ELSE LastSuccesProcessedAt END WHERE Id=@Id;"+
                " IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;";
            Dts.TaskResult=(int)DTSExecResult.Success;
        }
