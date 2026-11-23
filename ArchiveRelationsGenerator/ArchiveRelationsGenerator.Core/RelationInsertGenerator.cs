using System.Text;
using System.Text.RegularExpressions;

namespace ArchiveRelationsGenerator.Core;

public sealed record GenerationResult(string Sql, int RelationCount, int DuplicateCount);

public static class RelationInsertGenerator
{
    private sealed record Edge(string Parent, string ParentKey, string Child, string ChildKey, string ForeignKey);
    private static readonly string[] Required = ["ParentTable", "ParentKeyColumn", "ChildTable", "ChildKeyColumn"];

    public static GenerationResult Generate(string input, string database)
    {
        database = database.Trim();
        if (string.IsNullOrWhiteSpace(database) || database.Length > 128 || database.Any(char.IsControl))
            throw new FormatException("Podaj nazwę bazy źródłowej (maksymalnie 128 znaków).");
        if (string.IsNullOrWhiteSpace(input)) throw new FormatException("Wklej wynik zapytania skopiowany z siatki SSMS.");
        if (Regex.IsMatch(input.TrimStart(), @"^(DECLARE|SELECT|;?WITH|USE)\b", RegexOptions.IgnoreCase))
            throw new FormatException("Wklej wiersze z Results w SSMS, a nie kod zapytania SQL. Użyj Copy with Headers.");

        Dictionary<string, int>? header = null;
        var edges = new List<Edge>();
        int lineNumber = 0;
        foreach (var raw in input.Split('\n'))
        {
            lineNumber++;
            var line = raw.TrimEnd('\r');
            if (string.IsNullOrWhiteSpace(line) || Regex.IsMatch(line.Trim(), @"^\(\d+ (rows? affected|wiersz.*)\)$", RegexOptions.IgnoreCase)) continue;
            if (line.Trim().All(c => c is '-' or ' ' or '\t')) continue;
            var cells = line.Contains('\t') ? line.Split('\t').Select(c => c.Trim().Trim('\uFEFF')).ToArray()
                : Regex.Split(line.Trim(), @"\s{2,}");
            if (cells.Any(c => c.Equals("ParentTable", StringComparison.OrdinalIgnoreCase)))
            {
                header = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < cells.Length; i++)
                    if (cells[i].Length > 0 && !header.TryAdd(cells[i], i))
                        throw new FormatException($"Wiersz {lineNumber}: powtórzony nagłówek {cells[i]}.");
                if (Required.Any(c => !header.ContainsKey(c)))
                    throw new FormatException("Nagłówek musi zawierać ParentTable, ParentKeyColumn, ChildTable i ChildKeyColumn.");
                continue;
            }
            try
            {
                string Field(string name)
                {
                    if (header is not null)
                    {
                        if (!header.TryGetValue(name, out int index)) return "";
                        if (index >= cells.Length) throw new FormatException("Wiersz ma mniej kolumn niż nagłówek.");
                        return cells[index];
                    }
                    int shift = cells.Length == 11 ? 1 : 0;
                    if (cells.Length is 10 or 11)
                        return cells[name switch { "ParentTable" => 2+shift, "ParentKeyColumn" => 3+shift,
                            "ChildTable" => 4+shift, "ChildKeyColumn" => 5+shift, "ForeignKeyName" => 1+shift,
                            "ColumnPosition" => 6+shift, "IsDisabled" => 8+shift, "IsCycle" => 9+shift, _ => throw new FormatException("Nieznana kolumna.") }];
                    if (cells.Length == 4)
                        return name switch { "ParentTable" => cells[0], "ParentKeyColumn" => cells[1], "ChildTable" => cells[2], "ChildKeyColumn" => cells[3], _ => "" };
                    throw new FormatException("Oczekiwano wyniku SSMS rozdzielonego tabulatorami: 10 kolumn, opcjonalnie numer wiersza, lub 4 kolumn relacji.");
                }
                if (Field("IsDisabled") is "1" || Field("IsDisabled").Equals("true", StringComparison.OrdinalIgnoreCase))
                    throw new FormatException("Relacja ma wyłączony FK (IsDisabled=1). Zweryfikuj ją przed dodaniem do archiwizacji.");
                if (Field("IsCycle") is "1" || Field("IsCycle").Equals("true", StringComparison.OrdinalIgnoreCase))
                    throw new FormatException("Relacja jest częścią cyklu (IsCycle=1).");
                string position = Field("ColumnPosition");
                if (position.Length > 0 && (!int.TryParse(position, out int p) || p != 1))
                    throw new FormatException("Wykryto złożony FK. Obecny format ArchiveJobRelations nie obsługuje łączenia po kilku kolumnach jako jednego warunku.");
                edges.Add(new Edge(Table(Field("ParentTable")), Identifier(Field("ParentKeyColumn")),
                    Table(Field("ChildTable")), Identifier(Field("ChildKeyColumn")), Field("ForeignKeyName")));
            }
            catch (FormatException e) { throw new FormatException($"Wiersz {lineNumber}: {e.Message}", e); }
        }
        if (edges.Count == 0) throw new FormatException("Nie znaleziono wierszy relacji do wygenerowania.");
        foreach (var fk in edges.Where(e => e.ForeignKey.Length > 0).GroupBy(e => (e.Parent + "\0" + e.Child + "\0" + e.ForeignKey), StringComparer.OrdinalIgnoreCase))
            if (fk.Select(e => e.ParentKey + "\0" + e.ChildKey).Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1)
                throw new FormatException($"Klucz {fk.First().ForeignKey} zawiera kilka par kolumn. Nie można zapisać go jako niezależnych relacji.");
        var unique = edges.DistinctBy(e => string.Join('\0', e.Parent, e.ParentKey, e.Child, e.ChildKey), StringComparer.OrdinalIgnoreCase).ToList();
        CheckCycles(unique);
        var sql = new StringBuilder();
        foreach (var batch in unique.Chunk(1000))
        {
            if (sql.Length > 0) sql.AppendLine();
            sql.AppendLine("INSERT INTO Archive.ArchiveJobRelations (");
            sql.AppendLine("    DatabaseName, ParentTable, ChildTable, ParentKeyColumn, ChildKeyColumn");
            sql.AppendLine(")");
            sql.AppendLine("VALUES");
            sql.AppendLine(string.Join("," + Environment.NewLine, batch.Select(e =>
                $"    ({Literal(database)}, {Literal(e.Parent)}, {Literal(e.Child)}, {Literal(e.ParentKey)}, {Literal(e.ChildKey)})")) + ";");
        }
        return new GenerationResult(sql.ToString(), unique.Count, edges.Count-unique.Count);
    }

    private static string Literal(string value) => "N'" + value.Replace("'", "''") + "'";
    private static string Table(string value)
    {
        var parts = Parts(value);
        if (parts.Count != 2) throw new FormatException($"Tabela '{value}' musi mieć format schema.Tabela.");
        return string.Join('.', parts);
    }
    private static string Identifier(string value)
    {
        var parts = Parts(value);
        if (parts.Count != 1) throw new FormatException($"Nieprawidłowa nazwa kolumny '{value}'.");
        return parts[0];
    }
    private static List<string> Parts(string value)
    {
        var parts = new List<string>();
        int i = 0;
        while (i < value.Length)
        {
            while (i < value.Length && char.IsWhiteSpace(value[i])) i++;
            var name = new StringBuilder();
            if (i < value.Length && value[i] == '[')
            {
                i++; bool closed = false;
                while (i < value.Length)
                {
                    char c = value[i++];
                    if (c != ']') { name.Append(c); continue; }
                    if (i < value.Length && value[i] == ']') { name.Append(']'); i++; continue; }
                    closed = true; break;
                }
                if (!closed) throw new FormatException($"Niedomknięta nazwa '{value}'.");
            }
            else while (i < value.Length && value[i] != '.') name.Append(value[i++]);
            string part = name.ToString().Trim();
            if (part.Length is 0 or > 128 || part.Equals("NULL", StringComparison.OrdinalIgnoreCase) || part.Any(char.IsControl) || part.Contains('.'))
                throw new FormatException($"Nieprawidłowa nazwa '{value}'.");
            parts.Add(part);
            while (i < value.Length && char.IsWhiteSpace(value[i])) i++;
            if (i == value.Length) break;
            if (value[i++] != '.' || i == value.Length) throw new FormatException($"Nieprawidłowa nazwa '{value}'.");
        }
        if (parts.Count == 0) throw new FormatException("Brak nazwy tabeli lub kolumny.");
        return parts;
    }
    private static void CheckCycles(List<Edge> edges)
    {
        var graph = edges.GroupBy(e => e.Parent, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.Select(e => e.Child).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), StringComparer.OrdinalIgnoreCase);
        var states = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        // Iterative DFS also handles long pasted chains without overflowing the call stack.
        foreach (var root in graph.Keys)
        {
            if (states.ContainsKey(root)) continue;
            var stack = new Stack<(string Node, bool Exit)>(); stack.Push((root, false));
            while (stack.TryPop(out var item))
            {
                if (item.Exit) { states[item.Node] = 2; continue; }
                if (states.TryGetValue(item.Node, out int state))
                { if (state == 1) throw new FormatException($"Wykryto cykl zależności przy tabeli {item.Node}."); continue; }
                states[item.Node] = 1; stack.Push((item.Node, true));
                if (graph.TryGetValue(item.Node, out var children))
                    foreach (var child in children.Reverse()) stack.Push((child, false));
            }
        }
    }
}
