        public void Main()
        {
            string database = Convert.ToString(Dts.Variables["User::DatabaseName"].Value);
            Dts.Variables["User::ValidationRoot"].Value = Convert.ToString(Dts.Variables["User::TableName"].Value);
            string query = "USE [" + database.Replace("]", "]]") + "]; " +
                "IF ISNULL(HAS_PERMS_BY_NAME(DB_NAME(),N'DATABASE',N'VIEW DEFINITION'),0)<>1 " +
                "THROW 50020,'Archive FK validation requires VIEW DEFINITION on the source database.',1; " +
                "SELECT fk.object_id AS ForeignKeyId,fk.name AS ForeignKeyName," +
                "ps.name AS ParentSchema,pt.name AS ParentTable,pc.name AS ParentKeyColumn," +
                "cs.name AS ChildSchema,ct.name AS ChildTable,cc.name AS ChildKeyColumn," +
                "fc.constraint_column_id AS ColumnPosition,fk.delete_referential_action_desc AS DeleteRule," +
                "fk.is_disabled AS IsDisabled FROM sys.foreign_keys fk " +
                "JOIN sys.foreign_key_columns fc ON fc.constraint_object_id=fk.object_id " +
                "JOIN sys.tables pt ON pt.object_id=fc.referenced_object_id JOIN sys.schemas ps ON ps.schema_id=pt.schema_id " +
                "JOIN sys.columns pc ON pc.object_id=pt.object_id AND pc.column_id=fc.referenced_column_id " +
                "JOIN sys.tables ct ON ct.object_id=fc.parent_object_id JOIN sys.schemas cs ON cs.schema_id=ct.schema_id " +
                "JOIN sys.columns cc ON cc.object_id=ct.object_id AND cc.column_id=fc.parent_column_id " +
                "ORDER BY fk.object_id,fc.constraint_column_id;";
            // EXEC restores database context, preserving two-part config table names.
            Dts.Variables["User::ForeignKeysSql"].Value = "EXEC(N'" + query.Replace("'", "''") + "');";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
