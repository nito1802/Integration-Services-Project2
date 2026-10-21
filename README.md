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

`DatabaseName` wybiera bazę źródłową przez pełną nazwę tabeli `[baza].[schemat].[tabela]` w przygotowywanym SQL. `ArchiveDb` używa bazowego parametru `ConnectionString` i `RetainSameConnection = true`, aby wszystkie kroki widziały tę samą `#ArchiveDay`. Sesja nie zmienia bieżącej bazy między zadaniami. Nie ma `ChangeDatabase`, otwierania połączeń ani wykonywania SQL w C#. `ArchiveJobsDb` może wskazywać inny serwer. Użytkownik pakietu potrzebuje dostępu do źródeł, katalogu archiwum i 7-Zip.

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
    │   ├── Initialize daily archive — ścieżki, granice dnia i treść SQL
    │   ├── Stage archive day — Execute SQL Task, kopia dnia do #ArchiveDay
    │   ├── Process daily batches
    │   │   ├── Prepare batch select query — stronicowanie tabeli tymczasowej
    │   │   ├── Read archive batch — Execute SQL Task
    │   │   └── Write batch to CSV — nowy CSV z nagłówkiem
    │   ├── Verify exported day — liczba zapisanych wierszy vs #ArchiveDay
    │   ├── Create daily ZIP — Execute Process Task
    │   ├── Verify ZIP integrity — Execute Process Task
    │   ├── Delete archived day — Execute SQL Task, DELETE źródła po kluczach #ArchiveDay
    │   ├── Verify deleted row count
    │   ├── Drop staged day — Execute SQL Task, również po błędzie
    │   └── Delete temporary CSV files — tylko po sukcesie dnia
    ├── Save job result
    └── Log job result
Check overall archive result
```

Granica retencji jest ustalana raz na zadanie według daty serwera SQL:

```sql
SELECT CONVERT(datetime2(7),
    DATEADD(day, -@Days, CONVERT(date, GETDATE()))) AS CutoffDate;
```

Przetwarzanie zaczyna się od najstarszego kwalifikującego się dnia i kończy przed `CutoffDate`. `Stage archive day` kopiuje pełny zakres dnia:

```sql
SELECT * INTO #ArchiveDay
FROM [Baza].[Schemat].[Tabela]
WHERE KolumnaDaty >= @From AND KolumnaDaty < @To;
```

Powyżej pokazano logiczną postać filtra; rzeczywisty SQL zawiera typowane daty ISO, bez parametrów zewnętrznych, aby lokalna tabela tymczasowa nie była tworzona w zagnieżdżonym zakresie procedury. Sprawdzany jest brak NULL w kluczach, a licznik snapshotu trafia do `DayRows`. Cały dzień zajmuje miejsce w tempdb; C# pobiera tylko bieżącą partię do pamięci.

Każda partia jest odczytywana z niezmienianej tabeli tymczasowej w kolejności unikalnego klucza:

```sql
SELECT * FROM #ArchiveDay
ORDER BY Klucz1, Klucz2
OFFSET @ZapisaneWiersze ROWS FETCH NEXT @Limit ROWS ONLY;
```

`@Limit` oznacza `MaxRecordsPerCsv`; offset rośnie dopiero po udanym zapisie, Flush i zamknięciu CSV. W wykonywanym zapytaniu są to nieujemne literały liczbowe. Nie pobieramy ponownie tych samych rekordów i nie czytamy źródła między partiami. Pusty odczyt kończy pętlę. `Verify exported day` wymaga, by suma zapisanych wierszy zgadzała się z `DayRows`, zanim pakiet rozpocznie pakowanie.

Rekordy na granicy retencji i nowsze oraz daty NULL pozostają w źródle. Puste dni nie tworzą CSV ani ZIP. Ich pusta tabela tymczasowa i folder roboczy są sprzątane.
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

Oba bloczki pomijają dni bez plików oraz zadania z błędem. Dopiero po udanym utworzeniu i sprawdzeniu ZIP wykonywany jest DELETE źródła; po sprawdzeniu licznika usuwane są robocze CSV. Niezerowy kod 7-Zip (również ostrzeżenie) oznacza błąd; CSV pozostają. Nieudany ZIP także pozostaje do diagnostyki, a jego obecność nie potwierdza sukcesu zadania.

CSV: separator `;`, UTF-8 z BOM, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, nagłówki `Nazwa (typ SQL)`, `NULL` jako puste pole, wartości formatowane z `InvariantCulture`; daty i czas w formacie zachowującym precyzję (`o` / `c`), float/double w formacie `R`, dane binarne jako `0x` + zapis szesnastkowy. Zawartość pola może obejmować nowe linie, więc limit dotyczy rekordów CSV, nie fizycznych linii tekstu.

## Zapis, usuwanie i błędy

Kolejność dnia: kopia źródła do `#ArchiveDay` → zapis wszystkich CSV → kontrola liczby zapisanych wierszy → utworzenie ZIP → test integralności ZIP → DELETE źródła przez JOIN z kluczami `#ArchiveDay` → kontrola liczby usuniętych wierszy → DROP tabeli tymczasowej → usunięcie roboczych CSV.

Nie ma XML/base64, `BatchKeys`, przesyłania kluczy z C# do SQL ani `IDENTITY_INSERT`. Oryginalne wartości i typy kluczy pozostają w kopii SQL. `DROP TABLE #ArchiveDay` usuwa tylko kopię; źródło usuwa osobny DELETE. Nowy rekord dodany do źródła po utworzeniu kopii nie znajduje się w JOIN i pozostaje w bazie.

Błąd odczytu, CSV lub ZIP blokuje DELETE całego bieżącego dnia: źródłowe dane dnia pozostają w bazie, a utworzone CSV/ZIP są zachowane do sprawdzenia. Tabela tymczasowa jest sprzątana także po błędzie, a kolejne zadanie nadal jest przetwarzane. Błąd DELETE również zachowuje pliki. Dni zakończone wcześniej poprawnie nie są wycofywane.

Nie ma atomowej transakcji plik–baza. Przerwanie po utworzeniu ZIP, a przed DELETE pozostawia dane w obu miejscach; ponowienie napotka ochronę istniejącego folderu/ZIP. Zakładamy jedno aktywne przetwarzanie tabeli oraz brak zmian już istniejących historycznych rekordów podczas archiwizacji. Kontrola licznika po DELETE wykrywa rozbieżność, lecz nie cofa usunięcia.
Metadane pochodzą z krótkiego zapytania do `sys.dm_exec_describe_first_result_set` w trybie browse. SQL Server zwraca nazwy kolumn, pełne definicje typów i oznaczenie kolumn klucza unikalnego. Nie ma ręcznego przeglądania indeksów ani odtwarzania długości, precyzji i skali typów. C# przygotowuje nagłówek oraz łączy wynik z typami CLR pustego SELECT. Brak rozpoznanego klucza lub NULL w wartości klucza oznacza błąd. Funkcja wymaga SQL Server 2012 lub nowszego; jej pole `is_hidden` opisuje wynik funkcji i nie jest kolumną `sys.columns.is_hidden`.

Nazwy tabel i kolumn daty pochodzą z zaufanej konfiguracji i są wstawiane do SQL bez cytowania; parametry zadań Single row / None są wiązane. Zadania Full result set otrzymują gotowe zapytania bez zewnętrznych parametrów; literał nazwy tabeli w zapytaniu metadanych ma podwojone apostrofy, a daty i limit powstają wyłącznie z typowanych wartości. Zakładamy kolumnę daty `datetime2`. Partie z #ArchiveDay mają stabilną kolejność po rozpoznanych kolumnach klucza.

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

Wszystkie połączenia przepływu używają zielonego warunku `Success`. Dla błędów tabeli `OnError` ustawia `JobFailed`, a `ForceExecutionResult = Success` umożliwia dojście do zapisu wyniku i kolejnej tabeli. Warunki przy ZIP pozostają bez zmian.

Wyniki aktualnego przepływu z kopią dnia i DELETE po ZIP: `verification/daily-snapshot-results.md`.
