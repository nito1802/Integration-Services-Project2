# Archiwizacja CSV w SSIS

Solucja zawiera też bibliotekę C# `Integration Services Project2.Database` z niezależną tabelą `Archive.ArchiveJobs`, ośmioma rekordami przykładowymi i migracjami EF Core. Instrukcja `Add-Migration` / `Update-Database` bez osobnej aplikacji: [README biblioteki](Integration%20Services%20Project2.Database/README.md).

Otwórz `Integration Services Project2.slnx`, następnie `Package.dtsx` w SSIS Packages. Użyj **Execute Package** z menu kontekstowego pakietu (albo ustaw pakiet jako StartUp Object i użyj F5).

Wynik: **jeden CSV na tabelę na uruchomienie**, np. `C:\Archive\2026-10-08\MyData.Snapshots_2026-10-08_GUID.csv`.

Folder i data w nazwie pochodzą z daty rozpoczęcia pakietu. GUID jest generowany raz dla każdej tabeli. Kolejne uruchomienie tworzy nowy plik w tym samym folderze dnia, bez nadpisywania wcześniejszych wyników. Nie ma podfolderów dni danych ani plików TXT. Pusta tabela daje CSV z samym nagłówkiem.

Przepływ: Get Casher Settings → Foreach Loop Container (tabele) → BeginScript → Count days diff → GetGuid (inicjalizacja pliku) → For Loop Container (dni) → Get DateTo → Count records → Loop through 1000 → Construct SQL → Export data to CSV → Complete day. Po pętli dni Finalize table publikuje gotowy CSV.

Wszystkie dni i partie dopisują dane do wspólnego `.csv.tmp`. Nagłówek i BOM zapisują się raz. Po sprawdzeniu liczby rekordów tabeli plik jest przemianowany na `.csv`. Błąd zatrzymuje przebieg i pozostawia `.tmp` jako wynik nieukończony. Nowe uruchomienie otrzymuje nowy GUID i nie dopisuje do przerwanego eksportu.

Format CSV zachowuje eksport z projektu: separator `;`, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, nagłówki `Nazwa (typ SQL)`, UTF-8 z BOM, NULL jako puste pole, formatowanie invariant culture. Kolumny są odczytywane na nowo przy każdym uruchomieniu. Zmiana nagłówka podczas jednego eksportu powoduje błąd, aby nie mieszać struktur w jednym pliku.

Jeżeli istnieje `dbo.CasherSettings`, pakiet przetwarza rekordy `DictionaryType = 'Archiwum'`, według `Id`. Kolumny konfiguracji: `Id, TableName, Days, ColumnDate, ArchiwumPath`. `TableName` zapisuj jako `schema.table`, bez nawiasów. Przykład: `CasherSettings.example.sql`. Gdy tabela nie istnieje, pakiet używa parametrów `TableName`, `DateColumn`, `OlderThanDays`, `ArchiveRoot`. `SettingsQuery` pozwala dostosować zapytanie konfiguracji, zachowując kolejność pięciu kolumn. Parametr `OutputFile` pozostaje dla zgodności; wynikową ścieżkę wyznacza przepływ.

Eksport obejmuje wszystkie rekordy kwalifikujące się według obecnej retencji: pełne dni przed północą serwera SQL minus `Days`, zakresy `[DateFrom, DateTo)`. Wymagana jest kolumna date/datetime/datetime2/smalldatetime i niefiltrowany unikalny klucz, także złożony. Dzienna porcja trafia do tabeli tymczasowej w zachowanym połączeniu i jest czytana w partiach maksymalnie 1000 rekordów. Odczyt porcji używa krótkiej transakcji z HOLDLOCK; wymaga miejsca w tempdb i może blokować zapisy podczas kopiowania. Tabele źródłowe nie są zmieniane.

Źródła Script Tasks: `scripts`. `tools/Build-Package.ps1` osadza kod i skompilowane biblioteki przy użyciu Visual Studio 18 Insiders / SSIS 2025. Oryginalny pakiet: `tools/original.Package.dtsx`.

Weryfikacja: `tools/Verify-MainExport.ps1` porównuje najnowszy CSV bieżącej tabeli z bazą. `tools/Verify-Export.ps1` sprawdza test LocalDB: wiele tabel/dni/partii, IDENTITY, klucz złożony, pusta tabela, granica retencji, Unicode, średniki, cudzysłowy, tekst wielowierszowy, NULL i format liczb. `-ExpectedRuns 2` sprawdza ponowny eksport po dodaniu kolumny testowej. Konfiguracja: `verification/latest-config.txt`.

Potwierdzone wykonania w Visual Studio: główny eksport 95 rekordów w jednym CSV; test LocalDB 3508 rekordów w dwóch plikach danych i jeden CSV z nagłówkiem dla pustej tabeli; ponowne uruchomienie po dodaniu kolumny tworzy nowe CSV i pozostawia poprzednie pliki bez zmian. Wyniki sprawdzeń zapisano w katalogu ostatniego testu.
