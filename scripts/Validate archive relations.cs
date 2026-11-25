        private static string Node(string schema, string table)
        {
            return "[" + schema.Replace("]", "]]") + "].[" + table.Replace("]", "]]") + "]";
        }

        public void Main()
        {
            string root = Convert.ToString(Dts.Variables["User::ValidationRoot"].Value);
            string[] parts = root.Split('.');
            if (parts.Length != 2) throw new InvalidOperationException("Root table must contain schema.table.");
            string rootNode = Node(parts[0].Trim().Trim('[', ']'), parts[1].Trim().Trim('[', ']'));
            var configured = ((DataSet)Dts.Variables["User::RelationsData"].Value).Tables[0];
            var physical = ((DataSet)Dts.Variables["User::ForeignKeysData"].Value).Tables[0];
            var reachable = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { rootNode };
            var edges = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (DataRow edge in configured.Rows)
                edges.Add(Node(Convert.ToString(edge["ParentSchema"]), Convert.ToString(edge["ParentTable"])) + "\0" +
                    Node(Convert.ToString(edge["ChildSchema"]), Convert.ToString(edge["ChildTable"])) + "\0" +
                    Convert.ToString(edge["ParentKeyColumn"]) + "\0" + Convert.ToString(edge["ChildKeyColumn"]));
            bool expanded;
            do
            {
                expanded = false;
                foreach (DataTable table in new[] { configured, physical })
                    foreach (DataRow edge in table.Rows)
                    {
                        string parent = Node(Convert.ToString(edge["ParentSchema"]), Convert.ToString(edge["ParentTable"]));
                        if (reachable.Contains(parent))
                            expanded |= reachable.Add(Node(Convert.ToString(edge["ChildSchema"]), Convert.ToString(edge["ChildTable"])));
                    }
            } while (expanded);
            var problems = new List<string>();
            HashSet<string> planned = null;
            string step = Convert.ToString(Dts.Variables["System::TaskName"].Value);
            if (step != "Validate archive relations")
            {
                planned = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { rootNode };
                var plan = ((DataSet)Dts.Variables["User::ArchiveMembers"].Value).Tables[0];
                foreach (DataRow member in plan.Rows)
                    if (Convert.ToString(member["ChildSchema"]).Length > 0)
                        planned.Add(Node(Convert.ToString(member["ChildSchema"]), Convert.ToString(member["ChildTable"])));
            }
            foreach (DataRow fk in physical.Rows)
            {
                string parent = Node(Convert.ToString(fk["ParentSchema"]), Convert.ToString(fk["ParentTable"]));
                if (!reachable.Contains(parent)) continue;
                string child = Node(Convert.ToString(fk["ChildSchema"]), Convert.ToString(fk["ChildTable"]));
                string parentKey = Convert.ToString(fk["ParentKeyColumn"]), childKey = Convert.ToString(fk["ChildKeyColumn"]);
                if (planned != null && !planned.Contains(child))
                    problems.Add("Foreign-key child is missing from the archive plan: " + child + "; FK=" + fk["ForeignKeyName"]);
                if (Convert.ToInt32(fk["ColumnPosition"]) > 1)
                    problems.Add("Unsupported composite FK: " + fk["ForeignKeyName"] + " (" + parent + " -> " + child + ").");
                if (!edges.Contains(parent + "\0" + child + "\0" + parentKey + "\0" + childKey))
                    problems.Add("Missing relation in ArchiveJobRelations: " + parent + ".[" + parentKey + "] -> " + child + ".[" + childKey +
                        "]; DeleteRule=" + fk["DeleteRule"] + "; FK=" + fk["ForeignKeyName"] + "; IsDisabled=" + fk["IsDisabled"]);
            }
            if (problems.Count > 0) throw new InvalidOperationException(string.Join(Environment.NewLine, problems.ToArray()));
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
