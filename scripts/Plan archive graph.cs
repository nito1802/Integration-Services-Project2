        private static string Quote(string name)
        {
            return "[" + name.Replace("]", "]]") + "]";
        }

        public void Main()
        {
            string root = Convert.ToString(Dts.Variables["User::ParentTableName"].Value);
            string database = Quote(Convert.ToString(Dts.Variables["User::DatabaseName"].Value));
            var edges = ((DataSet)Dts.Variables["User::RelationsData"].Value).Tables[0];
            var pending = new Dictionary<string, List<DataRow>>(StringComparer.Ordinal);
            foreach (DataRow edge in edges.Rows)
            {
                string child = Quote(Convert.ToString(edge["ChildSchema"])) + "." + Quote(Convert.ToString(edge["ChildTable"]));
                if (!pending.ContainsKey(child)) pending.Add(child, new List<DataRow>());
                pending[child].Add(edge);
            }
            // Use the same quoted representation as relation entries.
            string[] parts = root.Split('.');
            if (parts.Length != 2) throw new InvalidOperationException("Root table must contain schema.table.");
            string rootKey = Quote(parts[0].Trim().Trim('[', ']')) + "." + Quote(parts[1].Trim().Trim('[', ']'));
            var indices = new Dictionary<string, int>(StringComparer.Ordinal);
            indices.Add(rootKey, 0);
            var plan = new DataTable();
            plan.Columns.Add("ChildSchema", typeof(string));
            plan.Columns.Add("ChildTable", typeof(string));
            plan.Columns.Add("ParentKeyColumn", typeof(string));
            plan.Columns.Add("ChildKeyColumn", typeof(string));
            plan.Columns.Add("SourceSql", typeof(string));
            plan.Rows.Add("", "", "", "", "SELECT * FROM #ArchiveParents");
            while (pending.Count > 0)
            {
                string ready = null;
                foreach (var node in pending)
                {
                    bool parentsReady = true;
                    foreach (DataRow edge in node.Value)
                    {
                        string schema = Convert.ToString(edge["ParentSchema"]);
                        string table = Convert.ToString(edge["ParentTable"]);
                        if ((schema.Length == 0) != (table.Length == 0))
                            throw new InvalidOperationException("Both parent schema and table must be specified.");
                        string parent = table.Length == 0 ? rootKey : Quote(schema) + "." + Quote(table);
                        if (!indices.ContainsKey(parent)) parentsReady = false;
                    }
                    if (parentsReady) { ready = node.Key; break; }
                }
                if (ready == null || indices.ContainsKey(ready))
                    throw new InvalidOperationException("Archive relations contain a cycle or a parent unreachable from the root.");
                var predicates = new List<string>();
                foreach (DataRow edge in pending[ready])
                {
                    string parentTable = Convert.ToString(edge["ParentTable"]);
                    string parent = parentTable.Length == 0 ? rootKey :
                        Quote(Convert.ToString(edge["ParentSchema"])) + "." + Quote(parentTable);
                    string snapshot = "#ArchiveMember" + indices[parent].ToString(CultureInfo.InvariantCulture);
                    predicates.Add("EXISTS (SELECT 1 FROM " + snapshot + " p WHERE p." +
                        Quote(Convert.ToString(edge["ParentKeyColumn"])) + "=c." +
                        Quote(Convert.ToString(edge["ChildKeyColumn"])) + ")");
                }
                DataRow first = pending[ready][0];
                indices.Add(ready, plan.Rows.Count);
                plan.Rows.Add(first["ChildSchema"], first["ChildTable"], "", "",
                    "SELECT c.* FROM " + database + "." + ready + " c WHERE " + string.Join(" OR ", predicates.ToArray()));
                pending.Remove(ready);
            }
            var result = new DataSet();
            result.Tables.Add(plan);
            Dts.Variables["User::ArchiveMembers"].Value = result;
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
