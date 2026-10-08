# Integration Services Project2.Console

W Visual Studio ustaw ten projekt jako **Set as Startup Project** i uruchom przez F5 lub Ctrl+F5. Program przekazuje gotową listę obiektów `ArchiveJob` do metody `ArchiveJobCreator.AddAsync(List<ArchiveJob> jobs)`. Listę edytuj w `Program.cs`; wstępnie zawiera zadania dla `MyData.Snapshots` i `SmartHome.Events`. Każde uruchomienie dodaje wszystkie rekordy z listy, również jeśli podobne zadania już istnieją.

`ArchiveJobCreator` otrzymuje `ArchiveJobsDbContext` przez konstruktor. `Program.cs` rejestruje kontekst i serwis w kontenerze DI. Zapis używa `SaveChangesAsync`; identyfikator nadaje SQL Server. Daty przetwarzania, status i błąd nowego zadania pozostają NULL do uruchomienia SSIS.

Program korzysta z tego samego `Integration Services Project2.Database/appsettings.json`, podlinkowanego do projektu i kopiowanego do katalogu wynikowego. Nie trzeba utrzymywać drugiej konfiguracji. Tabela musi wcześniej istnieć; program nie wykonuje migracji automatycznie. Istnienie tabeli źródłowej i kolumny daty sprawdza SSIS.

Z terminala w katalogu solucji:

```powershell
dotnet run --project "Integration Services Project2.Console"
```
