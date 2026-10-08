        public void Main()
        {
            Run(delegate {
                long rows = Convert.ToInt64(V("TableExportedRows"));
                if (rows != Convert.ToInt64(V("TableExpectedRows"))) throw new InvalidOperationException("Table export row count mismatch.");
                File.Move(S("OutputFile") + ".tmp", S("OutputFile"));
                Set("JobFilePublished", true);
                SqlConnection connection = Acquire();
                try
                {
                    using (var command = new SqlCommand("DECLARE @Now datetime2=SYSDATETIME(); UPDATE " + S("JobsTable") +
                        " SET LastSuccesProcessedAt=@Now, LastProcessedAt=@Now, LastProcessedStatus=N'Success', ErrorMessage=NULL WHERE Id=@Id; " +
                        "IF @@ROWCOUNT<>1 THROW 50001,'Archive job no longer exists.',1;", connection))
                    {
                        command.Parameters.Add("@Id", SqlDbType.Int).Value = V("ArchiveJobId");
                        command.ExecuteNonQuery();
                    }
                    // COMMIT must run outside the parameterized sp_executesql scope.
                    using (var commit = new SqlCommand("COMMIT TRANSACTION; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;", connection)) commit.ExecuteNonQuery();
                }
                finally { Release(connection); }
                Set("JobFilePublished", false);
                Set("JobActive", false);
                Info("Completed table=" + S("TableName") + "; rows=" + rows + "; path=" + S("OutputFile"));
            });
        }
