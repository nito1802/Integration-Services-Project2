# Archiwizacja CSV w SSIS

Pakiet `Integration Services Project2/Package.dtsx` pobiera zadania z `Archive.ArchiveJobs` i przetwarza **tabele → dni → partie CSV**. Każdy CSV ma własny nagłówek i maksymalnie konfigurowalną liczbę rekordów danych. Po zakończeniu dnia powstaje ZIP zawierający jego pliki CSV.

## Uruchomienie i parametry

Otwórz `Integration Services Project2.slnx` lub projekt `.dtproj`, następnie `Package.dtsx`. Uruchom pakiet przez F5 / Execute Package w Visual Studio z SSIS Projects. Projekt ma `TargetServerVersion = SQLServer2025`.

| Parametr pakietu | Znaczenie |
|---|---|
| `ConnectionString` | Połączenie `ArchiveDb` do serwera danych źródłowych. |
| `ArchiveJobsConnectionString` | Połączenie `ArchiveJobsDb` do konfiguracji i statusów. |
| `ArchiveRoot` | Katalog główny archiwum. |
| `MaxRecordsPerCsv` | Dodatni limit rekordów danych w jednym CSV; domyślnie `1000`. Nagłówek nie wlicza się do limitu. |
| `SevenZipPath` | Pełna ścieżka do `7z.exe`; domyślnie `C:\Program Files\7-Zip\7z.exe`. |

`DatabaseName` zadania wybiera bazę na serwerze źródłowym. Połączenia mogą wskazywać różne serwery. `ArchiveDb.ConnectionString` ma wyrażenie, które do bazowego connection stringa dodaje `Initial Catalog` z bieżącego `DatabaseName` (wartość jest cytowana). Nie ma `ChangeDatabase` ani otwierania połączeń w C#. `RetainSameConnection = false`: każdy SQL Task pobiera połączenie z aktualną konfiguracją. Tabela tymczasowa kluczy jest tworzona i używana wewnątrz jednego Execute SQL Task, więc nie wymaga współdzielonej sesji. Użytkownik uruchamiający pakiet musi mieć dostęp do katalogu archiwum i programu 7-Zip.

Schemat konfiguracji tworzy `CreateArchiveJobs.sql`, a przykład zadania znajduje się w `ArchiveJobs.example.sql`. Konfiguracja obejmuje `Id`, `DatabaseName`, `TableName`, `DateColumn`, `ArchiveOlderThanDays` oraz kolumny statusu `LastSuccesProcessedAt`, `LastProcessedAt`, `LastProcessedStatus`, `ErrorMessage`. Zachowano istniejącą pisownię `LastSuccesProcessedAt`.

## Przepływ

```text
Load archive jobs
└── For each archive job — zadania / tabele
    ├── Mark job as started
    ├── Initialize job variables
    ├── Prepare metadata and date queries — walidacja i przygotowanie treści SQL
    ├── Read column definitions — Execute SQL Task, pusty wynik z typami CLR
    ├── Read SQL types and keys — Execute SQL Task, systemowy opis wyniku SELECT
    ├── Prepare export schema and header — C#, przetwarzanie pobranych wyników
    ├── Calculate retention cutoff
    ├── Find first archive day — Execute SQL Task, MIN daty kwalifikujących się danych
    ├── For each archive day
    │   ├── Initialize daily archive — katalog roboczy, nagłówek, granice dnia
    │   ├── Process daily batches
    │   │   ├── Prepare batch select query
    │   │   ├── Read archive batch
    │   │   ├── Write batch to CSV — nowy CSV z nagłówkiem
    │   │   ├── Prepare delete query and keys — C#, SQL i parametr XML kluczy
    │   │   ├── Delete exported batch — Execute SQL Task, tabela kluczy i DELETE
    │   │   └── Verify deleted row count
    │   ├── Create daily ZIP — Execute Process Task
    │   ├── Verify ZIP integrity — Execute Process Task
    │   └── Delete temporary CSV files
    ├── Save job result
    └── Log job result
Check overall archive result
```

Granica retencji jest ustalana raz na zadanie według daty serwera SQL:

```sql
SELECT CONVERT(datetime2(7),
    DATEADD(day, -@Days, CONVERT(date, GETDATE()))) AS CutoffDate;
```

Przetwarzanie zaczyna się od najstarszego kwalifikującego się dnia i kończy przed `CutoffDate`. Dla każdego dnia wykonywane jest:

```sql
SELECT TOP (@Limit) * FROM {Tabela}
WHERE {KolumnaDaty} >= @From AND {KolumnaDaty} < @To;
```

Powyżej pokazano logiczną postać filtra. W wykonywanym SQL limit pochodzi z `MaxRecordsPerCsv`, a granice są kolejnymi północami. C# zapisuje dodatni limit jako liczbę oraz daty w formacie ISO z jawnym `CONVERT(datetime2(7), ..., 126)`. Bloczek pełnego wyniku nie ma zewnętrznych mapowań parametrów, aby uniknąć problemów adaptera w SSDT. Rekordy na granicy retencji i nowsze oraz daty `NULL` pozostają w bazie. Partie nie łączą dni. Pusta partia kończy pętlę; nie tworzy CSV. Puste dni i puste tabele nie tworzą ZIP. Dla pustego dnia przejściowy katalog roboczy jest usuwany.

## Pliki i ZIP

Przykład dla 2500 rekordów jednego dnia przy limicie 1000:

```text
ArchiveRoot/
  dbo.Orders/
    2026/
      2026_10_01.zip
        2026_10_01_part1.csv   # 1000 rekordów + nagłówek
        2026_10_01_part2.csv   # 1000 rekordów + nagłówek
        2026_10_01_part3.csv   #  500 rekordów + nagłówek
```

Rok i dzień wynikają z daty danych. Przed rozpoczęciem eksportu dnia pakiet sprawdza, czy istnieje już jego ZIP albo katalog roboczy. Kolizja kończy zadanie błędem przed odczytem partii i usuwaniem danych; istniejące pliki pozostają bez zmian. Wymagane jest ręczne sprawdzenie wcześniejszych plików przed ponowieniem. Robocze CSV znajdują się obok ZIP, w katalogu `2026_10_01`. Nazwa katalogu tabeli koduje niedozwolone znaki jako `~XXXX`.

**ZIP jest tworzony przez bloczek Execute Process Task, konfigurowany w Execute Process Task Editor.** Script Task przygotowuje tylko ścieżki i argumenty, nie uruchamia procesu ani kompresji.

| Właściwość | Create daily ZIP | Verify ZIP integrity |
|---|---|---|
| `Executable` (expression) | `@[$Package::SevenZipPath]` | `@[$Package::SevenZipPath]` |
| `Arguments` (expression) | `@[User::ZipArguments]` | `@[User::ZipTestArguments]` |
| Polecenie 7-Zip | `a -tzip -y "plik.zip" "katalog\*.csv"` | `t -tzip "plik.zip"` |
| `SuccessValue` | `0` | `0` |
| `FailTaskIfReturnCodeIsNotSuccessValue` | `True` | `True` |
| `TimeOut` / `TerminateProcessAfterTimeOut` | 600 sekund / True | 600 sekund / True |

Oba bloczki pomijają dni bez plików oraz zadania z błędem. Dopiero po udanym utworzeniu i sprawdzeniu ZIP usuwane są robocze CSV. Niezerowy kod 7-Zip (również ostrzeżenie) oznacza błąd; CSV pozostają. Nieudany ZIP także pozostaje do diagnostyki, a jego obecność nie potwierdza sukcesu zadania.

CSV: separator `;`, UTF-8 z BOM, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, nagłówki `Nazwa (typ SQL)`, `NULL` jako puste pole, wartości formatowane z `InvariantCulture`. Zawartość pola może obejmować nowe linie, więc limit dotyczy rekordów CSV, nie fizycznych linii tekstu.

## Zapis, usuwanie i błędy

Kolejność partii: odczyt → kontrola schematu → nowy CSV z nagłówkiem → `Flush` i zamknięcie pliku → przekazanie kluczy → DELETE po wszystkich kolumnach klucza → kontrola liczby usuniętych rekordów. Brak klucza tabeli lub klucz z `NULL` oznacza błąd. C# serializuje klucze zapisanej partii do parametru tekstowego XML; wartości są kodowane base64, aby zachować także puste ciągi, Unicode, znaki kontrolne i klucze binarne. Execute SQL Task `Delete exported batch` odtwarza ich właściwe typy SQL, tworzy i wypełnia lokalną `#ArchiveBatchKeys`, a następnie wykonuje DELETE przez JOIN po wszystkich składowych klucza. Obsługa odziedziczonego `IDENTITY` odbywa się w tym SQL przez `SET IDENTITY_INSERT`. Cała tabela tymczasowa istnieje tylko w obrębie tego jednego bloczka; nie wykonujemy niezależnego `DELETE TOP`. Błąd odtworzenia kluczy przerywa bloczek przed DELETE.

DELETE następuje po trwałym zapisie CSV, **przed pakowaniem dnia**. Błąd pakowania pozostawia CSV zawierające już usunięte rekordy. Należy je zachować i spakować ponownie osobno; ponowne uruchomienie zadania nie odtworzy ich z bazy.

Nie ma atomowej transakcji plik–baza. Przerwanie po zapisie, ale przed DELETE może spowodować ponowny eksport tych samych rekordów. Wcześniejsze udane partie nie są wycofywane po późniejszym błędzie. Zakładamy jedno aktywne przetwarzanie danej tabeli i brak równoległych zmian historycznych danych. Kontrola liczby po DELETE nie cofa usunięcia przy rozbieżności.

Metadane pochodzą z krótkiego zapytania do `sys.dm_exec_describe_first_result_set` w trybie browse. SQL Server zwraca nazwy kolumn, pełne definicje typów i oznaczenie kolumn klucza unikalnego. Nie ma ręcznego przeglądania indeksów ani odtwarzania długości, precyzji i skali typów. C# przygotowuje nagłówek oraz łączy wynik z typami CLR pustego SELECT. Brak rozpoznanego klucza lub NULL w wartości klucza oznacza błąd. Funkcja wymaga SQL Server 2012 lub nowszego; jej pole `is_hidden` opisuje wynik funkcji i nie jest kolumną `sys.columns.is_hidden`.

Nazwy tabel i kolumn daty pochodzą z zaufanej konfiguracji i są wstawiane do SQL bez cytowania; parametry zadań Single row / None są wiązane. Zadania Full result set otrzymują gotowe zapytania bez zewnętrznych parametrów; literał nazwy tabeli w zapytaniu metadanych ma podwojone apostrofy, a daty i limit powstają wyłącznie z typowanych wartości. Zakładamy kolumnę daty `datetime2`. Kolejność wierszy wewnątrz dnia nie jest gwarantowana.

Zdarzenia `OnError` zapisują `JobFailed` i `JobError` oraz zatrzymują propagację. Wymuszony wynik zadania pozwala dojść do `Save job result`, lecz nie oznacza sukcesu archiwizacji. Po błędzie kolejne operacje są pomijane, a obie pętle kończą się. Status `Error` zachowuje poprzednie `LastSuccesProcessedAt`; `Success` ustawia datę ostatniego sukcesu. Kolejne zadania są przetwarzane, a `Check overall archive result` kończy pakiet błędem, jeśli którekolwiek zadanie się nie udało. Błąd odczytu konfiguracji lub zapisu statusu zatrzymuje pakiet.

## Budowanie i weryfikacja

Aktywne źródła Script Tasks znajdują się w `scripts`. Samo edytowanie `.cs` nie aktualizuje pakietu. `tools/Build-Package.ps1` buduje przepływ, kompiluje skrypty i osadza je w `Package.dtsx`; `tools/Set-PackageLayout.ps1` ustawia diagram. Wymagana jest lokalna instalacja Visual Studio 18 Insiders / SSIS 2025. Historyczne pliki skryptów wykonujących SQL zostały zastąpione komentarzami o wycofaniu; dawne implementacje są w historii Git. Stare weryfikatory tych Script Tasks nie odpowiadają aktualnemu przepływowi.

```powershell
.\tools\Build-Package.ps1
.\tools\Build-Package.ps1 -CompatibilityTest
.\tools\Verify-DailyArchive.ps1
```

Zestaw testów tworzy izolowane bazy LocalDB. Sprawdza 3508 rekordów, dokładne klucze zamówień, limit domyślny i limit 37, podział dat na 20 dni, nagłówki i zawartość ZIP, puste tabele, retencję, ponowienie oraz awarie zapisu, DELETE, pakowania i sprawdzania ZIP oraz kolizje istniejącego folderu i ZIP. Dodatkowo sprawdza wybór kolejnych baz przez connection manager oraz klucze złożone obejmujące GUID, varbinary (w tym puste), decimal, datetime, datetimeoffset, time, float i tekst z pustymi wartościami oraz znakami kontrolnymi. Każdy scenariusz awarii korzysta ze świeżej bazy.

Weryfikator uruchamia rzeczywiste Execute SQL Tasks i źródła C# z pomocniczym hostem. Lokalny runtime blokuje Execute Process Task poza SSDT wymaganiem Standard Edition SSIS; domyślnie host testowy uruchamia 7-Zip z konfiguracją odczytaną z tych bloczków. `Verify-SqlTasks.ps1 -NativeProcessTasks` sprawdza rzeczywiste Execute Process Tasks, gdy runtime na to pozwala. **Pełny scheduler, pętle i zdarzenia wymagają dodatkowego uruchomienia F5 w Visual Studio.** `-FullPackage` wymaga odpowiednio licencjonowanego runtime poza SSDT.

Projekty `.Console` i `.Database` mają oddzielne README i konfigurację połączeń; ich konfiguracja nie zastępuje parametrów pakietu.

Wyniki aktualnej weryfikacji opisuje `verification/daily-archive-results.md`.

Wszystkie operacje bazodanowe aktywnego pakietu są Execute SQL Tasks. C# przygotowuje SQL i parametry, przetwarza pobrane DataSety, zapisuje CSV oraz obsługuje pliki i stan zadania. Nie wykonuje SQL ani nie pobiera połączeń. Pakowanie i test ZIP pozostają Execute Process Tasks.

Weryfikacja wersji bez operacji bazodanowych w C#: `verification/execute-sql-only-results.md`.
