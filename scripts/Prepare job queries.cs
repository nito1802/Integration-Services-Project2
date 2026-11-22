        private static string ConfigurationTable(string value, string parameter)
        {
            string[] parts = value.Split('.');
            if (parts.Length != 2 && parts.Length != 3)
                throw new ArgumentException(parameter + " must contain schema.table or database.schema.table.");
            for (int i = 0; i < parts.Length; i++)
            {
                string name = parts[i].Trim();
                if (name.StartsWith("[") && name.EndsWith("]"))
                    name = name.Substring(1, name.Length - 2).Replace("]]", "]");
                if (string.IsNullOrWhiteSpace(name) || name.Length > 128)
                    throw new ArgumentException("Invalid database, schema or table in " + parameter + ".");
                parts[i] = "[" + name.Replace("]", "]]") + "]";
            }
            return string.Join(".", parts);
        }

        public void Main()
        {
            string table = ConfigurationTable(
                Convert.ToString(Dts.Variables["$Package::ArchiveJobsTable"].Value), "ArchiveJobsTable");
            string relationsTable = ConfigurationTable(
                Convert.ToString(Dts.Variables["$Package::ArchiveJobRelationsTable"].Value), "ArchiveJobRelationsTable");
            Dts.Variables["User::MembersSelectSql"].Value =
                "IF OBJECT_ID(N'" + relationsTable.Replace("'", "''") + "',N'U') IS NULL " +
                "SELECT CONVERT(sysname,N'') AS ChildSchema,CONVERT(sysname,N'') AS ChildTable," +
                "CONVERT(sysname,N'') AS ParentKeyColumn,CONVERT(sysname,N'') AS ChildKeyColumn," +
                "CONVERT(sysname,N'') AS ParentSchema,CONVERT(sysname,N'') AS ParentTable WHERE 1=0; ELSE " +
                "SELECT PARSENAME(ChildTable,2) AS ChildSchema,PARSENAME(ChildTable,1) AS ChildTable,ParentKeyColumn,ChildKeyColumn," +
                "COALESCE(PARSENAME(NULLIF(ParentTable,N''),2),N'') AS ParentSchema," +
                "COALESCE(PARSENAME(NULLIF(ParentTable,N''),1),N'') AS ParentTable FROM " +
                relationsTable + " WHERE ArchiveJobId=@Id AND DatabaseName=@DatabaseName ORDER BY Id;";
            Dts.Variables["User::JobsSelectSql"].Value="SELECT Id, DatabaseName, TableName, ArchiveOlderThanDays, DateColumn FROM "+table+" ORDER BY Id;";
            Dts.Variables["User::JobStartSql"].Value="UPDATE "+table+" SET ErrorMessage=NULL, LastProcessedAt=SYSDATETIME(), LastProcessedStatus=NULL WHERE Id=@Id; IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;";
            Dts.Variables["User::JobResultSql"].Value="DECLARE @Now datetime2=SYSDATETIME(); UPDATE "+table+
                " SET LastProcessedAt=@Now, LastProcessedStatus=CASE WHEN @Failed=1 THEN N'Error' ELSE N'Success' END,"+
                " ErrorMessage=CASE WHEN @Failed=1 THEN @Error ELSE NULL END,"+
                " LastSuccesProcessedAt=CASE WHEN @Failed=0 THEN @Now ELSE LastSuccesProcessedAt END WHERE Id=@Id;"+
                " IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;";
            Dts.TaskResult=(int)DTSExecResult.Success;
        }
