# Integration Services Project2.Database

Biblioteka C# (.NET 10, EF Core 10.0.3) utrzymuje tabelę `Archive.ArchiveJobs`, z której SSIS pobiera zadania i w której zapisuje wyniki przetwarzania.

| Kolumna | C# | SQL Server |
|---|---|---|
| Id | int | int IDENTITY, PK |
| DatabaseName | string | nvarchar(128), wymagane |
| TableName | string | nvarchar(257), wymagane |
| DateColumn | string | nvarchar(128), wymagane |
| ArchiveOlderThanDays | int | int, wymagane |
| LastSuccesProcessedAt | DateTime? | datetime2, NULL przed pierwszym sukcesem |
| LastProcessedAt | DateTime? | datetime2, NULL przed pierwszą próbą |
| LastProcessedStatus | ArchiveJobStatus? | nvarchar(16), Error / Success / NULL |
| ErrorMessage | string? | nvarchar(max), NULL bez błędu |

Pisownia `LastSuccesProcessedAt` jest zachowana zgodnie z zamówioną nazwą. Typy i długości są określone atrybutami na encji `ArchiveJob`. Konwersja enumu na tekst używa `HasConversion<string>()` w kontekście. Daty zapisuje SSIS przez `SYSDATETIME()` serwera SQL. Przy sukcesie obie daty są identyczne; błąd nie zmienia daty ostatniego sukcesu.

Pierwsza migracja tworzy tabelę i osiem przykładowych rekordów. `AddArchiveJobProcessingState` zachowuje istniejące rekordy i daty, rozszerza model oraz ustawia `DateColumn=CreatedAt`. Poprawia też nazwy bazy dwóch znanych wpisów, w których wcześniej podano nazwę schematu. Model nie używa już `HasData`: konfiguracja i stany są zmieniane podczas pracy, więc kolejne migracje nie powinny ich nadpisywać ani usuwać. Historia migracji: `Archive.__EFMigrationsHistory`.

Jedynym źródłem połączenia biblioteki jest `ConnectionStrings:ArchiveJobsDatabase` w wymaganym `appsettings.json`, kopiowanym do katalogu wynikowego. Plik jest wykluczony z Gita ze względu na hasło; po sklonowaniu repozytorium trzeba go utworzyć. Połączenie SSIS ustawia się osobno w parametrze pakietu.

Migracje można wykonywać bez API i aplikacji konsolowej. `ArchiveJobsDbContextFactory` implementuje `IDesignTimeDbContextFactory<ArchiveJobsDbContext>`, konfiguruje SQL Server i schemat historii. Kontekst przyjmuje opcje w konstruktorze; nie potrzebuje `OnConfiguring` ani konstruktora bez parametrów.

W Package Manager Console w Visual Studio:

```powershell
Add-Migration NextChange -Project "Integration Services Project2.Database" -StartupProject "Integration Services Project2.Database" -Context ArchiveJobsDbContext
Update-Database -Project "Integration Services Project2.Database" -StartupProject "Integration Services Project2.Database" -Context ArchiveJobsDbContext
```

Alternatywnie z katalogu biblioteki:

```powershell
dotnet ef migrations add NextChange --context ArchiveJobsDbContext
dotnet ef database update --context ArchiveJobsDbContext
dotnet ef migrations has-pending-model-changes --context ArchiveJobsDbContext
```

Obie migracje zastosowano do uzgodnionej bazy. Sprawdzenie modelu nie wykazało oczekujących zmian. Skrypt `tools/Verify-ArchiveJobsDatabase.ps1` weryfikuje aktualną strukturę tabeli. Test SSIS obejmuje sukces, błąd, ponowienie i błąd podczas finalizacji eksportu.
