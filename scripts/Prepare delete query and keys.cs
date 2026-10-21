        public void Main()
        {
            var keys=(DataTable)Dts.Variables["User::BatchKeys"].Value;
            var matches=new List<string>(); var projections=new List<string>(); var columns=new List<string>(); var xml=new StringBuilder("<keys>");
            foreach(DataRow row in keys.Rows) {
                xml.Append("<r>");
                for(int i=0;i<keys.Columns.Count;i++) {
                    object value=row[i]; if(value==DBNull.Value) throw new InvalidOperationException("Archive key must not contain NULL.");
                    byte[] bytes;
                    if(value is byte[]) bytes=(byte[])value;
                    else {
                        string text;
                        if(value is DateTime) text=((DateTime)value).ToString("o",CultureInfo.InvariantCulture);
                        else if(value is DateTimeOffset) text=((DateTimeOffset)value).ToString("o",CultureInfo.InvariantCulture);
                        else if(value is TimeSpan) text=((TimeSpan)value).ToString("c",CultureInfo.InvariantCulture);
                        else if(value is double) text=((double)value).ToString("R",CultureInfo.InvariantCulture);
                        else if(value is float) text=((float)value).ToString("R",CultureInfo.InvariantCulture);
                        else if(value is bool) text=(bool)value?"1":"0";
                        else text=Convert.ToString(value,CultureInfo.InvariantCulture);
                        bytes=Encoding.Unicode.GetBytes(text);
                    }
                    xml.Append("<k").Append(i).Append(" v=\"").Append(Convert.ToBase64String(bytes)).Append("\"/>");
                }
                xml.Append("</r>");
            }
            xml.Append("</keys>");
            for(int i=0;i<keys.Columns.Count;i++) {
                var column=keys.Columns[i]; string name="["+column.ColumnName.Replace("]","]]")+"]";
                string binary="n.r.value('xs:base64Binary((k"+i+"/@v)[1])','varbinary(max)')";
                string value=column.DataType==typeof(byte[])?binary:"CONVERT(nvarchar(max),"+binary+")";
                if(column.DataType==typeof(DateTime)) value="CONVERT(datetime2(7),"+value+",127)";
                columns.Add(name);
                projections.Add("CONVERT("+Convert.ToString(column.ExtendedProperties["SqlType"])+","+value+")");
                matches.Add("s."+name+"=k."+name);
            }
            Dts.Variables["User::BatchKeysXml"].Value=xml.ToString();
            // The SQL task receives keys as a parameter. No connection or SQL execution occurs here.
            string names=string.Join(",",columns.ToArray());
            string table=Convert.ToString(Dts.Variables["User::TableName"].Value);
            Dts.Variables["User::DeleteSql"].Value="SET NOCOUNT ON; BEGIN TRY DECLARE @Document xml=CONVERT(xml,@Keys); "+
                "SELECT TOP (0) "+names+" INTO #ArchiveBatchKeys FROM "+table+"; "+
                "DECLARE @HasIdentity bit=CASE WHEN EXISTS(SELECT 1 FROM tempdb.sys.columns WHERE object_id=OBJECT_ID('tempdb..#ArchiveBatchKeys') AND is_identity=1) THEN 1 ELSE 0 END; "+
                "IF @HasIdentity=1 SET IDENTITY_INSERT #ArchiveBatchKeys ON; "+
                "INSERT INTO #ArchiveBatchKeys ("+names+") SELECT "+string.Join(",",projections.ToArray())+" FROM @Document.nodes('/keys/r') n(r); "+
                "IF @HasIdentity=1 SET IDENTITY_INSERT #ArchiveBatchKeys OFF; "+
                "DELETE s FROM "+table+" s INNER JOIN #ArchiveBatchKeys k ON "+string.Join(" AND ",matches.ToArray())+"; "+
                "DECLARE @Deleted bigint=@@ROWCOUNT; DROP TABLE #ArchiveBatchKeys; SELECT @Deleted AS DeletedRows; END TRY BEGIN CATCH THROW; END CATCH;";
            Dts.TaskResult=(int)DTSExecResult.Success;
        }
