# Integration Services Project2.Database

Biblioteka C# (.NET 10, EF Core 10.0.3) wzorowana na `SmartHome_BE.Database`: `DbContext`, interfejs kontekstu, `DbSet`, konfiguracja SQL Server, domyślny schemat i migracje EF Core. Encja znajduje się w `Entities`, bez dodatkowych kolumn audytowych.

Tabela: `Archive.ArchiveJobs` w bazie wskazanej przez connection string. Kolumny:

| Kolumna | C# | SQL Server |
|---|---|---|
| Id | int | int IDENTITY, klucz główny |
| DatabaseName | string | nvarchar(128), wymagane |
| TableName | string | nvarchar(257), wymagane |
| LastSuccesProcessedAt | DateOnly | date, wymagane |
| ArchiveOlderThanDays | int | int, wymagane |

Pisownia `LastSuccesProcessedAt` jest zachowana zgodnie z zamówioną nazwą. Pierwsza migracja `CreateArchiveJobs` tworzy tabelę i dodaje osiem przykładowych rekordów. Dane są zróżnicowane, ale zapisane na stałe przez `HasData`, aby generowanie kolejnych migracji nie losowało nowych wartości.

Historia migracji tej biblioteki: `Archive.__EFMigrationsHistory`. Biblioteka nie jest podłączona do przepływu SSIS i nie zmienia sposobu eksportowania CSV.

## Połączenie

Jedynym źródłem połączenia jest `ConnectionStrings:ArchiveJobsDatabase` w wymaganym pliku `appsettings.json`. Zawiera on uzgodnione połączenie z serwerem i jest kopiowany do katalogu wynikowego biblioteki. Aby zmienić połączenie, edytuj ten plik. Plik jest wykluczony z Gita ze względu na hasło; po sklonowaniu repozytorium należy go utworzyć z własnym połączeniem.

## Migracje bez API / aplikacji konsolowej

Tak — biblioteka jest projektem docelowym i uruchomieniowym narzędzi EF. `ArchiveJobsDbContextFactory` implementuje `IDesignTimeDbContextFactory<ArchiveJobsDbContext>`, a projekt zawiera pakiety Design/Tools i generuje runtimeconfig.

W Package Manager Console w Visual Studio:

```powershell
Add-Migration NextChange -Project "Integration Services Project2.Database" -StartupProject "Integration Services Project2.Database" -Context ArchiveJobsDbContext
Update-Database -Project "Integration Services Project2.Database" -StartupProject "Integration Services Project2.Database" -Context ArchiveJobsDbContext
```

Alternatywnie, w terminalu, z katalogu biblioteki (z zainstalowanym `dotnet-ef`):

```powershell
dotnet ef migrations add NextChange --context ArchiveJobsDbContext
dotnet ef database update --context ArchiveJobsDbContext
```

Pierwsza migracja jest już zastosowana do uzgodnionej bazy. Kolejnej migracji używaj po zmianie modelu. Ponowne `Update-Database` na aktualnej bazie nie dodaje drugi raz przykładowych rekordów.

## Weryfikacja

Potwierdzono kompilację bez błędów i ostrzeżeń, wygenerowanie migracji z samej biblioteki, zastosowanie jej w uzgodnionej bazie, pięć kolumn o zadanych typach, osiem rekordów i brak oczekujących zmian modelu. Ponowne `database update` zgłasza, że baza jest aktualna. Skrypt `tools/Verify-ArchiveJobsDatabase.ps1` odczytuje i sprawdza tabelę.
