        public void Main()
        {
            var shape = ((DataSet)Dts.Variables["User::ShapeData"].Value).Tables[0];
            var metadata = ((DataSet)Dts.Variables["User::MetadataData"].Value).Tables[0];
            if (metadata.Rows.Count == 0) throw new InvalidOperationException("Archive table metadata is unavailable. Check table name and permissions.");
            if (shape.Columns.Count != metadata.Rows.Count) throw new InvalidOperationException("Unsupported or changed table schema.");
            var schema = new DataTable();
            schema.Columns.Add("ColumnName",typeof(string)); schema.Columns.Add("DataType",typeof(Type));
            schema.Columns.Add("SqlType",typeof(string)); schema.Columns.Add("IsKey",typeof(bool));
            var keys = new List<string>(); var header = new List<string>();
            for (int i=0;i<metadata.Rows.Count;i++) {
                var row=metadata.Rows[i]; string name=Convert.ToString(row["ColumnName"]);
                if (name != shape.Columns[i].ColumnName) throw new InvalidOperationException("Table columns changed during metadata read.");
                bool isKey=row["IsKey"]!=DBNull.Value && Convert.ToBoolean(row["IsKey"]);
                string sqlType=Convert.ToString(row["SqlType"]);
                if(string.IsNullOrEmpty(sqlType)) throw new InvalidOperationException("Unsupported SQL type: "+name);
                string headerType=sqlType.Split('(')[0].Trim();
                if(headerType=="timestamp" || headerType=="rowversion") sqlType="varbinary(8)";
                if(isKey) { if(name.Contains(",")) throw new InvalidOperationException("Comma in key column name is not supported."); keys.Add(name); }
                schema.Rows.Add(name,shape.Columns[i].DataType,sqlType,isKey);
                header.Add("\""+(name+" ("+headerType+")").Replace("\"","\"\"")+"\"");
            }
            if(keys.Count==0) throw new InvalidOperationException("No unique non-null key: "+Convert.ToString(Dts.Variables["User::TableName"].Value));
            Dts.Variables["User::TableSchema"].Value=schema;
            Dts.Variables["User::KeyColumns"].Value=string.Join(", ",keys.ToArray());
            Dts.Variables["User::CsvHeader"].Value=string.Join(";",header.ToArray());
            Dts.TaskResult=(int)DTSExecResult.Success;
        }
