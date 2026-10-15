# Archiwizacja CSV w SSIS

Projekt `Integration Services Project2.Console` pozwala dodawać zadania do `Archive.ArchiveJobs`. Ustaw go jako startowy w Visual Studio i uruchom przez F5 / Ctrl+F5. Kontekst jest wstrzykiwany przez DI, a połączenie pochodzi z tego samego `appsettings.json` co biblioteka `.Database`. Instrukcja znajduje się w README konsolówki.

Otwórz `Integration Services Project2.slnx`, następnie `Package.dtsx` i użyj Execute Package lub F5. Konfigurację tabel pakiet pobiera z `Archive.ArchiveJobs`, według `Id`. Parametr `ConnectionString` wskazuje serwer danych źródłowych, `ArchiveJobsConnectionString` wskazuje bazę z konfiguracją i statusami `ArchiveJobs`, a `ArchiveRoot` katalog wynikowy. Połączenia mogą wskazywać różne serwery; `DatabaseName` zadania odnosi się do bazy na serwerze źródłowym. Dawne `SettingsQuery` i konfiguracja CasherSettings zostały usunięte.

Wynik to jeden CSV na tabelę na uruchomienie, np. `C:\Archive\2026-10-08\MyData.Snapshots_2026-10-08_GUID.csv`. Dzień w folderze pochodzi z daty rozpoczęcia pakietu. GUID zapobiega nadpisywaniu poprzednich eksportów. Nagłówek jest odczytywany na nowo dla każdej tabeli; pusta tabela daje sam nagłówek.

Konfiguracja `Archive.ArchiveJobs`:

| Kolumna | Znaczenie |
|---|---|
| Id | Klucz zadania |
| DatabaseName | Rzeczywista nazwa bazy na tym samym serwerze SQL |
| TableName | Nazwa `schema.table`, np. `MyData.Snapshots` |
| DateColumn | Kolumna daty, zwykle `CreatedAt` |
| ArchiveOlderThanDays | Retencja w pełnych dniach |
| LastSuccesProcessedAt | Data i czas ostatniego udanego eksportu |
| LastProcessedAt | Data i czas ostatniej próby |
| LastProcessedStatus | Tekst `Success` lub `Error`; NULL podczas przetwarzania / przed pierwszą próbą |
| ErrorMessage | Szczegóły ostatniego błędu, czyszczone przy rozpoczęciu próby |

`DatabaseName` nie jest nazwą schematu. Migracja poprawia dwa wcześniejsze przykładowe wpisy: `MyData.Snapshots` i `SmartHome.Events` należą do schematów w obecnej bazie `nito_superDb`. Pozostałe wcześniejsze wpisy demonstracyjne pozostają w tabeli; gdy wskazują nieistniejące bazy, otrzymują `Error`.

Przepływ: Get Archive Jobs → Foreach Loop Container → Start archive job → Prepare archive job → BeginScript → Count days diff → GetGuid → pętla dni → pętla partii (Construct SQL → Read archive batch → Export data to CSV → Prepare batch delete → Create batch key table → Stage batch keys → Delete exported batch → Check deleted rows) → SetTableStatus → Report archive job. Na końcu Archive summary podsumowuje wszystkie zadania. Complete day i Finalize table zostały usunięte.

Na początku zadania zapisujemy czas próby, czyścimy błąd i status. Nie używamy jawnych transakcji SQL ani transakcji SSIS. Dane są czytane bezpośrednio ze źródła; nie tworzymy `#ArchiveDay`. Zakres to pełne dni sprzed północy serwera SQL pomniejszonej o retencję. Zakładamy kolumnę daty typu datetime2; jej typ nie jest sprawdzany. Nazwy tabel i kolumn są wpisywane do SQL bez nawiasów kwadratowych, więc muszą być poprawnymi nazwami niewymagającymi cytowania (np. dbo.Orders i CreatedAt). Klucz do wskazania usuwanych rekordów, również złożony, odczytujemy przez GetSchemaTable i CommandBehavior.KeyInfo po SELECT TOP (0), bez jawnych zapytań do sys. Brak klucza zgłasza błąd. Partia używa SELECT TOP (1000) bez OFFSET i ORDER BY. Eksport zapamiętuje klucze maksymalnie 1000 rekordów, zamyka i flushuje CSV, a dopiero potem Delete exported batch usuwa dokładnie te klucze. Po zamknięciu CSV bloczek Create batch key table tworzy #ArchiveBatchKeys o typach i kolacjach kluczy źródła. Stage batch keys kopiuje do niej dokładne wartości przez SqlBulkCopy z KeepIdentity. Delete exported batch wykonuje DELETE JOIN, a Check deleted rows sprawdza licznik. RetainSameConnection utrzymuje tę samą sesję SQL między bloczkami; tabela tymczasowa jest odtwarzana dla każdej partii. Zakładamy jeden aktywny przebieg dla danej tabeli oraz brak zewnętrznych zmian historycznych rekordów w czasie jej przetwarzania.

Plik od początku ma rozszerzenie `.csv`. GetGuid tworzy plik i zapisuje jeden nagłówek; kolejne paczki dopisują dane. Nie ma pliku `.tmp`, przemianowania ani końcowego sprawdzania liczby rekordów dnia/tabeli. Nie ma Count records ani FileRecordCounter. Dla każdego dnia pętla pobiera TOP (1000), zapisuje CSV i usuwa tę paczkę aż zapytanie zwróci zero rekordów. BatchHasRows jest resetowane na true przy rozpoczęciu kolejnego dnia, a po każdej paczce przyjmuje wartość rows > 0.

Błąd odczytu, serializacji lub usuwania ustawia `JobFailed` i zapisuje wyjątek do `JobError`. Dalszy eksport tej tabeli jest pomijany. Końcowy bloczek Execute SQL Task `SetTableStatus`, wykonywany także po błędzie, aktualizuje `ArchiveJobs` przez osobne połączenie: przy sukcesie obie daty dostają identyczne `SYSDATETIME()`, status Success i pusty ErrorMessage; przy błędzie zapisuje datę próby, Error oraz komunikat, zachowując datę poprzedniego sukcesu. Błąd konfiguracji tabeli również daje Error. Jeżeli nie można odczytać konfiguracji lub zapisać stanu, pakiet zatrzymuje się.

Po błędzie plik `.csv` pozostaje na dysku i może zawierać tylko część danych. Samo rozszerzenie nie oznacza sukcesu — wynik zadania wskazuje LastProcessedStatus. Kolejne zadania są przetwarzane dalej, a Archive summary zgłasza końcowy błąd pakietu, jeśli którekolwiek zadanie miało Error. Nowa próba zawsze ma nowy GUID. Zapisane paczki są usuwane ze źródła. Błąd zapisu CSV nie uruchamia DELETE tej paczki. Przerwanie po zapisie CSV, ale przed DELETE, pozostawia dane również w bazie: ponowienie może zapisać je drugi raz do nowego pliku. Wcześniejsze udane usunięcia nie są wycofywane; taki częściowy CSV trzeba zachować.

Format CSV: separator `;`, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, UTF-8 z BOM, nagłówki `Nazwa (typ SQL)`, NULL jako puste pole, formatowanie invariant culture. Zmiana struktury podczas eksportu powoduje błąd.

Biblioteka `Integration Services Project2.Database` utrzymuje model i migracje. Instrukcja migracji bez osobnej aplikacji znajduje się w jej README. Konfiguracja biblioteki pochodzi z `appsettings.json`; połączenie SSIS jest osobnym parametrem pakietu.

Źródła Script Tasks są w `scripts`. Po ich zmianie `tools/Build-Package.ps1` osadza kod i kompiluje skrypty przy użyciu Visual Studio 18 Insiders / SSIS 2025. Samo edytowanie pliku w `scripts` nie aktualizuje osadzonego kodu pakietu.

Weryfikacja:

- `tools/Verify-ArchiveJobsDatabase.ps1`: dziewięć kolumn, typy datetime2 i tekstowy status.
- `tools/Verify-MainExport.ps1`: starszy weryfikator eksportu bez usuwania; nie stosować do nowego flow, bo zarchiwizowanych rekordów nie ma już w źródle.
- `tools/Create-TestDatabase.ps1 -IncludeFailure`: izolowany LocalDB z wieloma tabelami, kluczem złożonym, pustą tabelą i celowo błędnym zadaniem.
- `tools/Verify-JobProcessing.ps1`: kontynuacja po błędzie, wyczyszczenie poprzedniego błędu, zachowanie daty sukcesu; `-RetrySucceeded` sprawdza ponowienie po naprawie konfiguracji.
- `tools/Verify-Export.ps1`: dokładne klucze, retencja, wiele partii, Unicode, cudzysłowy, średniki, wielowierszowy tekst i BOM.

Poprzedni test eksportu bez usuwania: `verification/20261009_013119`. Pełny pakiet uruchomiony w Visual Studio wyeksportował 3508 rekordów i CSV z nagłówkiem dla pustej tabeli; kontrolowany błąd konfiguracji dał Error i nie zatrzymał kolejnych zadań. Dodatkowy test rzeczywistych źródeł ScriptMain, z zastąpionym interfejsem hosta SSIS, wymusił błąd po pierwszej paczce: pozostał CSV z 1000 rekordami, bez tmp, a SetTableStatus zapisał Error i zachował poprzednią datę sukcesu. Wyniki: `verification-result.txt`, `job-state-False.txt`, `partial-csv-result.txt`.

Historyczny test eksportu z usuwaniem (przed zmianą na Execute SQL Task): tools/Create-TestDatabase.ps1 -IncludeFailure, następnie tools/Verify-DeleteExport.ps1. Test uruchamia rzeczywiste źródła ScriptMain z zastąpionym hostem SSIS i prawdziwymi połączeniami do izolowanego LocalDB; nie uruchamia produkcyjnego serwera. Sprawdza dokładną zawartość 3508 rekordów w CSV, pozostawienie danych przy granicy retencji, ponowienie bez powtórnego eksportu usuniętych danych, błędy zapisu/usuwania, statusy i precyzyjny klucz datetime2(7). Wynik: verification/20261009_093243/delete-export-result.txt.

Od 2026-10-14 wykonywanie zapytań dotyczących konfiguracji, statusów, zakresu dni, odczytu partii oraz usuwania odbywa się w Execute SQL Task (7 bloczków). Połączenia pozostają ADO.NET; nie trzeba zmieniać ich na OLE DB. SQL dynamiczny pochodzi ze zmiennych, wartości parametrów są mapowane w Parameter Mapping, a wyniki przez Result Set (dla ADO.NET numerowane od 0). C# nadal przygotowuje SQL, zapisuje CSV, przenosi klucze przez SqlBulkCopy i odczytuje metadane przez SELECT TOP (0)/KeyInfo w BeginScript i GetGuid. Historyczne źródła Get Archive Jobs.cs, Start archive job.cs, Count days diff.cs, Delete exported batch.cs i SetTableStatus.cs nie są już osadzane w pakiecie; pozostają jako odniesienie dla starych weryfikatorów.

Bloczki SQL wewnątrz zadania mają OnError z Capture SQL error: zapis JobFailed/JobError i System::Propagate=false. Po błędzie przechodzimy przez połączenie Completion do kroku pomijającego dalszą pracę. Pętle kończą się przy JobFailed. Błąd pobrania konfiguracji lub zapisu statusu nadal kończy pakiet. Układ starego diagramu jest usuwany podczas budowania, aby projektant automatycznie rozmieścił aktualne zadania.

Aktualna weryfikacja (Windows PowerShell 5.1):

```powershell
.\tools\Build-Package.ps1
.\tools\Build-Package.ps1 -CompatibilityTest
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1
.\tools\Verify-SqlTasks.ps1 -Retry
# Każdy scenariusz błędu wymaga świeżej bazy:
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1 -FailureMode Write
.\tools\Create-TestDatabase.ps1 -IncludeFailure
.\tools\Verify-SqlTasks.ps1 -FailureMode Delete
```

Test korzysta z rzeczywistych TaskHost Execute SQL Task i ich mapowań, rzeczywistych źródeł C# z zastępczym hostem oraz izolowanej bazy LocalDB. Sprawdza 3508 rekordów, wiele partii, IDENTITY, klucz złożony, pustą tabelę, retencję, ponowienie, błędy zapisu/DELETE, zachowanie daty poprzedniego sukcesu i dalsze przetwarzanie. Zainstalowany runtime nie pozwala wykonywać całego pakietu poza SSDT (wymaga Standard Edition SSIS). Dlatego kolejność i reakcję na błędy SQL odtwarza skrypt testowy; harmonogram i wykonanie OnError pozostają do sprawdzenia w Visual Studio. Opcja -FullPackage wykonuje pełny pakiet, jeśli odpowiedni runtime jest dostępny. Starsze Verify-DeleteExport.ps1 i Verify-JobProcessing.ps1 nie sprawdzają nowego przepływu.

Wyniki: verification/20261014_161405/native-result.txt i native-retry-result.txt, verification/20261014_161538/native-result.txt (błąd zapisu), verification/20261014_161556/native-result.txt (błąd DELETE).