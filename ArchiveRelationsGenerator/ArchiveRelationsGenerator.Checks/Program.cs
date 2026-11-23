using ArchiveRelationsGenerator.Core;

int checks = 0;
void Check(bool condition, string message) { if (!condition) throw new Exception(message); checks++; }
void Reject(string input, string expected, string database = "test")
{
    try { RelationInsertGenerator.Generate(input, database); throw new Exception("Expected rejection: " + expected); }
    catch (FormatException e) { Check(e.Message.Contains(expected, StringComparison.OrdinalIgnoreCase), e.Message); }
}
var generated = RelationInsertGenerator.Generate(SampleData.Text, "nito_superDb");
Check(generated.RelationCount == 6, "Six screenshot relations");
Check(generated.Sql.Contains("N'GenericSignatureTest.AutentiProcesses', N'GenericSignatureTest.AutentiRecipients', N'EnvelopeId', N'EnvelopeId'"), "Grandchild mapping");
Check(!generated.Sql.Contains("[Generic"), "Brackets normalized");
Check(generated.Sql.StartsWith("INSERT INTO Archive.ArchiveJobRelations"), "Correct target");
Check(!generated.Sql.Contains("ArchiveJobId"), "No legacy job ID");
var lines = SampleData.Text.Split(Environment.NewLine);
Check(RelationInsertGenerator.Generate(string.Join(Environment.NewLine, lines.Skip(1)), "test").RelationCount == 6, "Without headers");
var numbered = "\t" + lines[0] + Environment.NewLine + string.Join(Environment.NewLine, lines.Skip(1).Select((line,i) => (i+1)+"\t"+line));
Check(RelationInsertGenerator.Generate(numbered, "test").RelationCount == 6, "Row numbers with headers");
Check(RelationInsertGenerator.Generate(string.Join(Environment.NewLine, lines.Skip(1).Select((line,i) => (i+1)+"\t"+line)), "test").RelationCount == 6, "Row numbers without headers");
var duplicate = RelationInsertGenerator.Generate(SampleData.Text+Environment.NewLine+lines[1], "test");
Check(duplicate.DuplicateCount == 1 && duplicate.RelationCount == 6, "Duplicate paths merged");
Check(RelationInsertGenerator.Generate("[dbo].[O'Brien]\t[Id]\t[dbo].[Child]\t[ParentId]", "Db'Name").Sql.Contains("N'Db''Name', N'dbo.O''Brien'"), "SQL literal escaping");
Check(RelationInsertGenerator.Generate("dbo.A\tId\tdbo.B\tAId\ndbo.A\tId\tdbo.C\tAId\ndbo.B\tId\tdbo.D\tBId\ndbo.C\tId\tdbo.D\tCId", "test").RelationCount == 4, "Diamond allowed");
Reject("dbo.A\tId\tdbo.B\tAId\ndbo.B\tId\tdbo.A\tBId", "cykl");
Reject(SampleData.Text.Replace("\t1\tCASCADE", "\t2\tCASCADE"), "złożony FK");
Reject(SampleData.Text.Replace("\t0\t0", "\t1\t0"), "wyłączony FK");
Reject(SampleData.Text.Replace("\t0\t0", "\t0\t1"), "cyklu");
Reject("DECLARE @StartTable nvarchar(257) = N'dbo.Processes';", "Results");
Reject("dbo.A\tId\tdbo.B\tAId", "nazwę bazy", "");
Reject("dbo.A\tId\tB\tAId", "schema.Tabela");
Reject("[dbo].[A\tId\tdbo.B\tAId", "Niedomknięta");
Reject(lines[0], "Nie znaleziono");
Reject(lines[0]+"\n1\tFK\tdbo.A", "mniej kolumn");
var bulk = RelationInsertGenerator.Generate(string.Join('\n', Enumerable.Range(0,1001).Select(i => $"dbo.Root\tId\tdbo.C{i}\tParentId")), "test");
Check(bulk.Sql.Split("INSERT INTO").Length-1 == 2 && bulk.RelationCount == 1001, "Batch limit");
Console.WriteLine($"PASS: {checks} checks (SSMS headers, row numbers, deduplication, escaping, composite keys, cycles, batching).");
