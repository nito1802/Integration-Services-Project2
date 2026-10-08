# Archiwizacja CSV w SSIS

Otwórz `Integration Services Project2.slnx`, następnie `Package.dtsx` w folderze SSIS Packages. Użyj **Execute Package** z menu kontekstowego pakietu (albo ustaw pakiet jako StartUp Object i użyj F5).

Przepływ: Get Casher Settings → Foreach Loop Container (tabele) → BeginScript → Count days diff → For Loop Container (dni) → Get DateTo → Count records → File System Task → Loop through 1000 → GetGuid → Construct SQL → Export data to CSV → Complete day.

Jeżeli istnieje `dbo.CasherSettings`, pakiet przetwarza rekordy `DictionaryType = 'Archiwum'`, według `Id`. Kolumny konfiguracji: `Id, TableName, Days, ColumnDate, ArchiwumPath`. `TableName` zapisuj jako `schema.table`, bez nawiasów. Przykład konfiguracji znajduje się w `CasherSettings.example.sql`. Gdy tabela nie istnieje, pakiet używa obecnych parametrów `TableName`, `DateColumn`, `OlderThanDays` i nowego `ArchiveRoot`. `SettingsQuery` pozwala dostosować zapytanie konfiguracji, zachowując kolejność pięciu kolumn. Dotychczasowy parametr `OutputFile` pozostaje w pakiecie; katalogi i nazwy plików wyznacza teraz wielokrokowy przepływ.

Eksport obejmuje pełne dni przed północą serwera SQL minus `Days`. Każdy dzień ma zakres `[DateFrom, DateTo)`. Wymagana jest kolumna date/datetime/datetime2/smalldatetime i niefiltrowany unikalny klucz. Pakiet wykrywa również klucze złożone. Dzienna porcja danych trafia do lokalnej tabeli tymczasowej w zachowanym połączeniu, po czym jest czytana stabilnie w partiach maksymalnie 1000 rekordów. Odczyt dziennej porcji używa krótkiej transakcji z HOLDLOCK; wymaga miejsca w tempdb i może blokować zapisy podczas kopiowania. Tabele źródłowe nie są zmieniane.

Format CSV zachowuje eksport z projektu: separator `;`, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, nagłówki `Nazwa (typ SQL)`, UTF-8 z BOM, NULL jako puste pole, formatowanie invariant culture. Pliki mają nazwy `part_001_GUID.csv` itd. w katalogu tabeli/dnia. Zapis przechodzi przez `.tmp`, następnie publikowany jest gotowy CSV. `_SUCCESS.txt` oznacza ukończony dzień. Niepusty istniejący katalog dnia powoduje błąd, aby ponowienie nie dublowało danych; przed ponowieniem sprawdź poprzedni eksport i wybierz nowy katalog główny.

Źródła Script Tasks znajdują się w `scripts`. `tools/Build-Package.ps1` osadza kod i skompilowane biblioteki w pakiecie przy użyciu zainstalowanego Visual Studio 18 Insiders / SSIS 2025. Oryginalny pakiet jest zachowany w `tools/original.Package.dtsx`.

Test pełnego przepływu wykonano w Visual Studio na izolowanej bazie LocalDB: wiele tabel, IDENTITY, klucz złożony, pusta tabela, pusty dzień, granica retencji, partie 1000/1000/505, znaki polskie, średniki, cudzysłowy, wielowierszowy tekst i NULL. Wynik: 7 CSV, 3508 rekordów, 4 ukończone dni. `tools/Verify-Export.ps1` sprawdza wynik wskazany w `verification/latest-config.txt`.

Główny projekt również uruchomiono w Visual Studio ze statusem Success: `MyData.Snapshots`, 90 dni retencji, 95 rekordów w 82 plikach CSV / katalogach dni w `C:\Archive\table_MyData~002ESnapshots`. `tools/Verify-MainExport.ps1` potwierdził zgodność wszystkich identyfikatorów i wartości pól z odczytem bazy, brak duplikatów, 82 znaczniki ukończenia i brak plików tymczasowych. Wynik sprawdzenia zapisano w katalogu ostatniego testu.
