# Archiwizacja CSV w SSIS

Pakiet `Integration Services Project2/Package.dtsx` odczytuje zadania z `Archive.ArchiveJobs`, eksportuje stare rekordy do CSV i usuwa ze źródła dokładnie rekordy zapisane do pliku. Dla każdego zadania powstaje osobny CSV i zapisywany jest wynik `Success` albo `Error`.

Ten opis dotyczy aktualnego przepływu: **dwie zagnieżdżone pętle — po zadaniach/tabelach oraz po partiach do 1000 rekordów. Nie ma pętli po dniach.**

## Uruchomienie i konfiguracja

Otwórz projekt SSIS przez `Integration Services Project2.slnx` lub `Integration Services Project2/Integration Services Project2.dtproj`, następnie `Package.dtsx`. Pakiet uruchamia się przez Execute Package / F5 w Visual Studio z rozszerzeniem SQL Server Integration Services Projects. Projekt ma `TargetServerVersion = SQLServer2025`.

| Parametr pakietu | Przeznaczenie |
|---|---|
| `ConnectionString` | Połączenie z serwerem danych źródłowych; używa go connection manager `ArchiveDb`. |
| `ArchiveJobsConnectionString` | Połączenie z bazą konfiguracji i statusów; używa go `ArchiveJobsDb`. |
| `ArchiveRoot` | Katalog główny wynikowych plików CSV. |

Połączenia mogą wskazywać różne serwery. `DatabaseName` w zadaniu wybiera bazę na serwerze źródłowym. Oba connection managery są ADO.NET. `ArchiveDb` ma `RetainSameConnection = true`: zmiana bieżącej bazy i tymczasowa tabela kluczy muszą być widoczne w kolejnych bloczkach tej samej sesji.

Schemat `Archive` i tabelę konfiguracji można utworzyć skryptem [CreateArchiveJobs.sql](CreateArchiveJobs.sql), bez uruchamiania migracji EF. Skrypt nie dodaje danych przykładowych, nie aktualizuje starszej struktury i pozostawia istniejącą tabelę bez zmian. Nie zapisuje historii migracji EF. Przykład dodania zadania znajduje się w [ArchiveJobs.example.sql](ArchiveJobs.example.sql).

| Kolumna `ArchiveJobs` | Znaczenie |
|---|---|
| `Id` | Identyfikator zadania; konfiguracja jest pobierana według rosnącego `Id`. |
| `DatabaseName` | Nazwa bazy źródłowej; nie jest nazwą schematu. |
| `TableName` | Nazwa tabeli wraz ze schematem, np. `dbo.Orders`. |
| `DateColumn` | Nazwa kolumny używanej do sprawdzania retencji; w skrypcie tworzenia tabeli nie ma wartości domyślnej. |
| `ArchiveOlderThanDays` | Dodatnia liczba dni retencji. |
| `LastSuccesProcessedAt` | Czas zakończenia ostatniego udanego zadania. Pisownia nazwy kolumny jest zachowana z istniejącego modelu. |
| `LastProcessedAt` | Czas rozpoczęcia próby, zastępowany czasem końcowego zapisu statusu. |
| `LastProcessedStatus` | `Success`, `Error` albo `NULL` przed pierwszym wykonaniem / podczas przetwarzania. |
| `ErrorMessage` | Szczegóły błędu; czyszczone na początku próby i przy sukcesie. |

`ArchiveJobStatus` jest enumem C#, nie osobną tabelą. `LastProcessedStatus` jest przechowywany jako `nvarchar(16)`; model EF ma `HasConversion<string>()`.

Projekt `Integration Services Project2.Console` pozwala dodawać zadania; można ustawić go jako startowy i uruchomić F5 / Ctrl+F5. Biblioteka `.Database` utrzymuje model i migracje. Oba projekty mają własne README. Ich `appsettings.json` jest niezależny od parametrów połączeń pakietu SSIS.

## Kolejność bloczków

```text
Get Archive Jobs
└── Foreach Loop Container — każde zadanie / tabela
    ├── Start archive job
    ├── Prepare archive job
    ├── BeginScript
    ├── Get cutoff date
    ├── GetGuid
    ├── Loop through 1000 — partie dla bieżącego zadania
    │   ├── Construct SQL
    │   ├── Read archive batch
    │   ├── Export data to CSV
    │   ├── Prepare batch delete
    │   ├── Create batch key table
    │   ├── Stage batch keys
    │   ├── Delete exported batch
    │   └── Check deleted rows
    ├── SetTableStatus
    └── Report archive job
Archive summary
```

### Przed pętlą po zadaniach

**1. Get Archive Jobs — Execute SQL Task.** Odczytuje z `ArchiveJobsDb` kolumny `Id`, `DatabaseName`, `TableName`, `ArchiveOlderThanDays`, `DateColumn`, posortowane po `Id`. Pełny wynik trafia do zmiennej Object `User::Tables`. Błąd odczytu konfiguracji kończy pakiet.

**2. Foreach Loop Container — pętla po zadaniach.** Iteruje po `User::Tables` przez Foreach ADO Enumerator. Mapuje kolumny wyniku do `ArchiveJobId`, `DatabaseName`, `TableName`, `Days` i `ColumnDate`. Dla każdego wiersza wykonuje kroki 3–18. To pętla po wpisach konfiguracji: dwa wpisy tej samej tabeli byłyby dwoma zadaniami.

### Przygotowanie bieżącego zadania

**3. Start archive job — Execute SQL Task.** Aktualizuje bieżący wpis w `ArchiveJobsDb`, używając parametru `@Id`. Ustawia `LastProcessedAt = SYSDATETIME()`, czyści `ErrorMessage` i ustawia `LastProcessedStatus = NULL`. Sprawdza, czy zmieniono dokładnie jeden wpis; brak wpisu zgłasza błąd. Nie zmienia daty ostatniego sukcesu. Niepowodzenie tego kroku zatrzymuje pakiet.

**4. Prepare archive job — Script Task.** Resetuje stan poprzedniego zadania: `JobActive = true`, `JobFailed = false`, `JobError = ""`, `OutputFile = ""`, `BatchHasRows = true`, `BatchNumber = 0`. Kopiuje parametr `ArchiveRoot` do `ArchiwumPath`. Pobiera połączenie `ArchiveDb`, wybiera `DatabaseName` przez `ChangeDatabase` i oddaje połączenie do SSIS w `finally`. Ten bloczek zawsze się wykonuje, również po błędzie poprzedniej tabeli. Nieistniejąca lub niedostępna baza jest błędem bieżącego zadania.

**5. BeginScript — Script Task.** Sprawdza, czy `Days > 0`. Wykonuje `SELECT TOP (0) * FROM tabela` z `CommandBehavior.KeyInfo`, żeby odczytać strukturę bez pobierania rekordów. Zapisuje metadane do `TableSchema`, a rozpoznane kolumny klucza do `KeyColumns`. Obsługuje klucze złożone; brak rozpoznanego klucza zgłasza wyjątek. Nie wylicza już pierwszego dnia ani liczby dni do przetworzenia.

**6. Get cutoff date — Execute SQL Task.** Ustala granicę raz na zadanie, według zegara serwera źródłowego:

```sql
SELECT CONVERT(datetime2(7),
    DATEADD(day, -@Days, CONVERT(date, GETDATE()))) AS CutoffDate;
```

`@Days` pochodzi z `User::Days`, a wynik `0` jest mapowany do `User::CutoffDate`. Granica jest północą bieżącego dnia SQL Servera pomniejszoną o retencję. Nie przesuwa się pomiędzy partiami. Przykładowo dla daty serwera 2026-10-15 i retencji 1 dzień eksportowane są rekordy z datą **mniejszą niż 2026-10-14 00:00:00**. Rekordy równe granicy i nowsze pozostają w bazie.

**7. GetGuid — Script Task.** Generuje GUID, bezpieczną nazwę pliku i katalog dnia rozpoczęcia pakietu. Odczytuje nazwy i typy SQL kolumn przez `SELECT TOP (0)`. Tworzy nowy CSV przez `FileMode.CreateNew` i zapisuje nagłówek. Przykładowy wynik: `C:\Archive\2026-10-15\dbo.Orders_2026-10-15_GUID.csv`. Kolejne partie dopisują dane do tego samego pliku. Tabela bez kwalifikujących się danych daje CSV z samym nagłówkiem. Nieudany późniejszy odczyt również może pozostawić taki plik.

### Pętla po partiach

**8. Loop through 1000 — For Loop Container.** Znajduje się bezpośrednio wewnątrz pętli po zadaniach. Zeruje `BatchNumber` i powtarza kroki 9–16, dopóki:

```text
!@[User::JobFailed] && @[User::BatchHasRows]
```

Zakończenie następuje po błędzie albo po pustym wyniku SELECT. Partia mniejsza niż 1000 nie kończy pętli sama w sobie — wykonywany jest jeszcze odczyt sprawdzający, czy pozostały dane. Partie mogą łączyć rekordy z wielu dni.

**9. Construct SQL — Script Task.** Buduje zapytanie w `User::SQLStatement`, podstawiając nazwę tabeli i kolumny daty:

```sql
SELECT TOP (1000) *
FROM {Tabela}
WHERE {KolumnaDaty} < @Cutoff;
```

Nie wykonuje zapytania. Nie ma `OFFSET`, dolnej granicy daty ani `ORDER BY`; kolejność rekordów nie jest gwarantowana. Każdy odczyt wybiera maksymalnie 1000 rekordów spełniających retencję. Usunięcie zapisanej partii pozwala kolejnemu odczytowi pobrać następne rekordy.

**10. Read archive batch — Execute SQL Task.** Wykonuje SQL ze zmiennej `User::SQLStatement` na `ArchiveDb`. Mapuje parametr `@Cutoff` z `User::CutoffDate`. Pełny wynik jest zapisywany jako DataSet w `User::BatchData`; timeout wynosi 300 sekund. Nieistniejąca kolumna daty zgłasza błąd tutaj. Na tym etapie nie zapisuje się CSV ani nie usuwa danych.

**11. Export data to CSV — Script Task.** Odczytuje `BatchData` i porównuje liczbę kolumn, ich nazwy oraz typy CLR z `TableSchema`. Dopisuje rekordy do wcześniej utworzonego CSV, a równolegle zapamiętuje ich klucze w DataTable. Klucz zawierający `NULL` zgłasza błąd. Po zapisie wykonuje `writer.Flush()` i `stream.Flush(true)`, po czym zamyka plik. Dopiero wtedy udostępnia klucze jako `User::BatchKeys`. Ustawia `BatchHasRows` na `rows > 0`, zwiększa `BatchNumber` i loguje tabelę, granicę daty, numer partii, liczbę rekordów, ścieżkę oraz czas. Błąd jest uzupełniany o kontekst pliku i partii, a następnie zgłaszany dalej do `OnError`.

**12. Prepare batch delete — Script Task.** Na podstawie `BatchKeys` buduje dwa zapytania: `PrepareKeysSql` do odtworzenia tabeli tymczasowej oraz `DeleteSql` do usunięcia rekordów przez połączenie po wszystkich kolumnach klucza. Nazwy kolumn klucza są cytowane nawiasami kwadratowymi. Ten krok tylko przygotowuje tekst SQL.

**13. Create batch key table — Execute SQL Task.** Wykonuje `PrepareKeysSql`: usuwa poprzednią `#ArchiveBatchKeys`, jeśli istnieje, i tworzy nową przez `SELECT TOP (0) ... INTO`. Kolumny pochodzą ze źródła, zachowując jego typy i kolacje. Zapytanie zawiera `CROSS JOIN (SELECT 1 AS n)`, aby nie przenosić właściwości `IDENTITY`. Tabela jest lokalna dla sesji `ArchiveDb` i jest odtwarzana dla każdej partii; nie przechowuje całej kopii danych źródłowych.

**14. Stage batch keys — Script Task.** Kopiuje `BatchKeys` do `#ArchiveBatchKeys` przez `SqlBulkCopy` z mapowaniem kolumn po nazwach, timeoutem 300 sekund i `KeepIdentity`. Przekazuje oryginalne wartości kluczy, również złożonych. Kopiowanie następuje dopiero po zamknięciu CSV. Błąd tego kroku blokuje DELETE.

**15. Delete exported batch — Execute SQL Task.** Wykonuje `DeleteSql` na `ArchiveDb`. `DELETE ... INNER JOIN #ArchiveBatchKeys` dopasowuje wszystkie składowe klucza, więc usuwa rekordy wskazane przez klucze zapisanej partii. Nie wykonuje niezależnego `DELETE TOP (1000)`. Zapytanie zwraca `CONVERT(bigint, @@ROWCOUNT)` mapowane z wyniku `0` do `User::DeletedRows`.

**16. Check deleted rows — Script Task.** Porównuje `DeletedRows` z liczbą wierszy w `BatchKeys`. Rozbieżność zgłasza wyjątek z liczbą usuniętych i wyeksportowanych rekordów. Sprawdzenie odbywa się po DELETE i nie cofa usunięcia. Po poprawnym sprawdzeniu pętla przechodzi do następnej partii. Po pustym odczycie dalsze kroki partii operują na pustym zestawie kluczy, a kolejna ocena warunku kończy pętlę.

### Zakończenie zadania i pakietu

**17. SetTableStatus — Execute SQL Task.** Wykonuje się po zakończeniu pętli partii, także gdy została przerwana przez `JobFailed`. Na osobnym połączeniu `ArchiveJobsDb` zapisuje wynik bieżącego zadania:

| Wynik | Zapis w `ArchiveJobs` |
|---|---|
| Sukces | `LastProcessedStatus = Success`, `ErrorMessage = NULL`; `LastProcessedAt` i `LastSuccesProcessedAt` dostają tę samą wartość `SYSDATETIME()`. |
| Błąd | `LastProcessedStatus = Error`, `ErrorMessage = JobError`, `LastProcessedAt` dostaje czas zapisu; poprzednie `LastSuccesProcessedAt` pozostaje bez zmian. |

Parametry to `@Id`, `@Failed` i `@Error`. Brak wpisu lub niepowodzenie aktualizacji zatrzymuje pakiet — nie można wtedy potwierdzić zapisu wyniku.

**18. Report archive job — Script Task.** Ustawia `JobActive = false`. Dla błędu zwiększa `FailedJobs`; zapisuje do logu nazwę tabeli, status i ścieżkę CSV. Następnie `Foreach Loop Container` przechodzi do następnego zadania. Jest to krok raportujący, a nie drugi zapis statusu do bazy.

**19. Archive summary — Script Task.** Działa raz, po zakończeniu pętli po zadaniach. Gdy `FailedJobs > 0`, zgłasza błąd z liczbą nieudanych zadań i ustawia wynik pakietu na `Failure`. W przeciwnym razie loguje sukces. Pakiet może więc przetworzyć poprawnie późniejsze tabele, a mimo to zakończyć się `Failure` z powodu wcześniejszych błędów.

## Obsługa błędów — bloczki Capture … error

Bloczki `Capture … error` są Script Tasks wewnątrz zdarzeń `OnError`, a nie kolejnymi krokami głównego przepływu. Wszystkie używają kodu z [scripts/Capture SQL error.cs](scripts/Capture%20SQL%20error.cs), również gdy błąd pochodzi z C#:

```csharp
Dts.Variables["User::JobFailed"].Value = true;
Dts.Variables["User::JobError"].Value =
    Convert.ToString(Dts.Variables["System::ErrorDescription"].Value);
Dts.Variables["System::Propagate"].Value = false;
Dts.TaskResult = (int)DTSExecResult.Success;
```

Handler zapisuje komunikat do zmiennych; do bazy zapisuje go dopiero `SetTableStatus`. Przy wielu zdarzeniach `OnError` późniejszy komunikat może zastąpić wcześniejszy.

| Bloczek główny | Script Task w `OnError` |
|---|---|
| Prepare archive job | Capture preparation error |
| BeginScript | Capture BeginScript error |
| Get cutoff date | Capture cutoff error |
| GetGuid | Capture GetGuid error |
| Construct SQL | Capture Construct SQL error |
| Read archive batch | Capture batch read error |
| Export data to CSV | Capture Export data to CSV error |
| Prepare batch delete | Capture Prepare batch delete error |
| Create batch key table | Capture key table error |
| Stage batch keys | Capture Stage batch keys error |
| Delete exported batch | Capture batch delete error |
| Check deleted rows | Capture Check deleted rows error |

Te zadania mają `FailPackageOnFailure = false`, `FailParentOnFailure = false`, `MaximumErrorCount = 0` i `ForceExecutionResult = Success`. Wymuszony wynik pozwala dojść do zapisu statusu; **nie oznacza sukcesu archiwizacji**. O nim decydują `JobFailed`, zapis w `ArchiveJobs` i końcowe podsumowanie.

Po błędzie kolejne operacje są pomijane przez wyrażenie `Disable = @[User::JobFailed]`, a pętla partii kończy się przez swój warunek. Wyjątkiem jest `Prepare archive job`, który zawsze resetuje stan przed następnym zadaniem. Wybrane połączenia po bloczkach SQL mają warunek `Completion`, aby przejść do kroku pomijającego pracę także po błędzie.

`Get Archive Jobs`, `Start archive job`, `SetTableStatus`, `Report archive job` i `Archive summary` nie mają mechanizmu kontynuacji błędu bieżącej tabeli. Skrypty nie używają helpera `Run`. Wyjątki C# mogą w debuggerze Visual Studio otworzyć osobne okno `DTS Script Task: Runtime Error`, które wymaga zamknięcia, aby test kontynuował wykonanie.

## Zasady zapisu i usuwania ważne dla review

- Kolejność to **odczyt → zapis i zamknięcie CSV → przekazanie kluczy → DELETE → kontrola liczby usuniętych rekordów**. Błąd zapisu nie uruchamia DELETE tej partii.
- Nie ma jawnej transakcji SQL ani transakcji SSIS obejmującej plik i bazę. Wcześniejsze udane usunięcia nie są wycofywane po późniejszym błędzie.
- Przerwanie między zapisem CSV a DELETE pozostawia rekordy również w źródle; ponowienie może wyeksportować je drugi raz do nowego pliku z nowym GUID.
- Częściowy CSV pozostaje na dysku i trzeba go zachować, bo wcześniejsze partie mogły już zostać usunięte. Rozszerzenie `.csv` nie potwierdza sukcesu; należy sprawdzić status zadania.
- Zakładamy jedno aktywne przetwarzanie danej tabeli oraz brak równoległych zmian historycznych rekordów. Odczyt i usunięcie nie są jedną atomową operacją.
- Nazwy tabel i kolumn daty w dynamicznym SQL pochodzą z zaufanej konfiguracji i nie są cytowane. Muszą być poprawnymi nazwami niewymagającymi cytowania, np. `dbo.Orders` i `CreatedAt`. Wartości dat i identyfikator zadania są parametryzowane.
- Zakładamy kolumnę daty typu `datetime2`; jej typ nie jest osobno walidowany. Warunek `< @Cutoff` nie obejmuje wartości `NULL`.
- Kontrola struktury przy eksporcie porównuje nazwy, liczbę kolumn i typy CLR. Nie wykrywa każdej zmiany definicji SQL, np. samej długości `nvarchar`.
- `Check deleted rows` sprawdza licznik partii. Nie ma końcowego porównania całej tabeli z CSV ani pliku `.tmp` i późniejszej zmiany nazwy.

CSV ma separator `;`, wszystkie pola w cudzysłowach, podwajanie cudzysłowów wewnątrz wartości, UTF-8 z BOM i nagłówki `Nazwa (typ SQL)`. `NULL` jest zapisywane jako puste pole. Wartości są formatowane przez `Convert.ToString(..., CultureInfo.InvariantCulture)`.

## Źródła i budowanie

Aktywne Script Tasks mają źródła w `scripts`. [tools/Build-Package.ps1](tools/Build-Package.ps1) składa przepływ, ustawia parametry i mapowania, kompiluje skrypty oraz osadza kod i DLL w `Package.dtsx`. Samo edytowanie pliku `.cs` nie aktualizuje pakietu. Budowanie korzysta z lokalnej instalacji Visual Studio 18 Insiders / SSIS 2025. [tools/Set-PackageLayout.ps1](tools/Set-PackageLayout.ps1) zapisuje układ diagramu, w tym wcięcia kontenerów i dwa rzędy bloczków partii.

Historyczne źródła `Get Archive Jobs.cs`, `Start archive job.cs`, `Count days diff.cs`, `Get DateTo.cs`, `Delete exported batch.cs` i `SetTableStatus.cs` pozostają w repozytorium dla starszych weryfikatorów; nie są aktywnymi Script Tasks obecnego pakietu. Źródłem prawdy dla aktywnych kroków jest `Package.dtsx` i jego skrypt budujący.

## Weryfikacja

Aktualny test w Windows PowerShell 5.1:

```powershell
.\tools\Build-Package.ps1
.\tools\Build-Package.ps1 -CompatibilityTest
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1 -SpreadDates
.\tools\Verify-SqlTasks.ps1 -Retry

# Każda wymuszona awaria wymaga świeżej bazy:
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1 -FailureMode Write
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1 -FailureMode Delete
```

Weryfikator korzysta z rzeczywistych TaskHost Execute SQL Task, ich parametrów i wyników, źródeł C# z zastępczym hostem oraz izolowanej LocalDB. Sprawdza 3508 rekordów, dokładne klucze CSV zamówień, klucz złożony, pustą tabelę, retencję, ponowienie, błędy zapisu i DELETE, zachowanie daty poprzedniego sukcesu oraz kontynuowanie kolejnych zadań. `SpreadDates` rozkłada dane zamówień na 20 dni; partie wynoszą `1000, 1000, 506, 0`, gdzie końcowe zero wykrywa koniec. Wyniki: `verification/20261015_121326` (eksport i ponowienie), `verification/20261015_121351` (błąd zapisu), `verification/20261015_121356` (błąd DELETE).

Test odtwarza kolejność zadań i obsługę zdarzeń przez pomocniczy host; nie uruchamia pełnego schedulera SSIS. Nowy przepływ bez podziału na dni wymaga osobnego pełnego uruchomienia w Visual Studio. Opcja `-FullPackage` wymaga runtime z uprawnieniem do wykonania całego pakietu poza SSDT; lokalna instalacja zgłasza wymóg Standard Edition SSIS.

Starsze wyniki pełnych crash testów w Visual Studio są w `verification/20261015_094342`; dotyczą wersji sprzed usunięcia pętli dni. Starsze `Verify-MainExport.ps1`, `Verify-Export.ps1`, `Verify-DeleteExport.ps1` i `Verify-JobProcessing.ps1` nie weryfikują aktualnego przepływu. `Verify-ArchiveJobsDatabase.ps1` sprawdza strukturę dziewięciu kolumn tabeli konfiguracji.
