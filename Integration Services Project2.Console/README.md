# Integration Services Project2.Console

## Dane testowe SmartHome.Events

```powershell
dotnet run --project "Integration Services Project2.Console" -- seed-events
```

`EventTestDataCreator.AddAsync()` dodaje dokładnie 50 000 rekordów w jednej transakcji do `SmartHome.Events` w bazie wskazanej przez istniejące połączenie `ArchiveJobsDatabase`. Każde uruchomienie dodaje nowy zestaw. Nie dodaje zadania archiwizacji.

Dni **2025-01-01–2025-01-20** mają po **2500 nowych rekordów** (dla limitu 1000: **1000 + 1000 + 500**, czyli 3 party na dzień). `CreatedAt` i `ExecutedAt` są jednakowe i rozłożone w obrębie dnia. Istniejące dane mogą zwiększyć liczbę partów. Użyte wartości `Name` to `OpenedExternally`/`ClosedExternally`, a `Type` to `Door`.

Każdy zestaw ma unikalny znacznik `SSIS-TEST-<guid>` w `Comment`; po nim jest `; row=<numer 1–50000>`. Konsola wypisuje znacznik, filtr SQL i dla każdego dnia liczbę rekordów oraz minimalne/maksymalne ID. Zakres ID może zawierać cudze rekordy przy równoczesnych zapisach — dokładny wybór zapewnia filtr po znaczniku:

```sql
SELECT * FROM SmartHome.Events
WHERE Comment LIKE N'SSIS-TEST-<guid z konsoli>; row=%'
ORDER BY CreatedAt, Id;
```

Generator wymaga istniejącej tabeli; nie uruchamia migracji. Aby uruchomić w Visual Studio, ustaw argument aplikacji na `seed-events`.

W Visual Studio ustaw ten projekt jako **Set as Startup Project** i uruchom przez F5 lub Ctrl+F5. Program przekazuje gotową listę obiektów `ArchiveJob` do metody `ArchiveJobCreator.AddAsync(List<ArchiveJob> jobs)`. Listę edytuj w `Program.cs`; wstępnie zawiera zadania dla `MyData.Snapshots` i `SmartHome.Events`. Każde uruchomienie dodaje wszystkie rekordy z listy, również jeśli podobne zadania już istnieją.

`ArchiveJobCreator` otrzymuje `ArchiveJobsDbContext` przez konstruktor. `Program.cs` rejestruje kontekst i serwis w kontenerze DI. Zapis używa `SaveChangesAsync`; identyfikator nadaje SQL Server. Daty przetwarzania, status i błąd nowego zadania pozostają NULL do uruchomienia SSIS.

Program korzysta z tego samego `Integration Services Project2.Database/appsettings.json`, podlinkowanego do projektu i kopiowanego do katalogu wynikowego. Nie trzeba utrzymywać drugiej konfiguracji. Tabela musi wcześniej istnieć; program nie wykonuje migracji automatycznie. Istnienie tabeli źródłowej i kolumny daty sprawdza SSIS.

Z terminala w katalogu solucji:

```powershell
dotnet run --project "Integration Services Project2.Console"
```
