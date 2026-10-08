# Archiwizacja CSV w SSIS

Otwórz `Integration Services Project2.slnx`, następnie `Package.dtsx` i użyj Execute Package lub F5. Konfigurację tabel pakiet pobiera z `Archive.ArchiveJobs`, według `Id`. Parametry pakietu to `ConnectionString` i `ArchiveRoot`. Dawne `SettingsQuery` i konfiguracja CasherSettings zostały usunięte.

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

Przepływ: Get Archive Jobs → Foreach Loop Container → Start archive job → BeginScript → Count days diff → GetGuid → pętla dni → pętla partii po 1000 → Finalize table. Na końcu Archive summary podsumowuje wszystkie zadania.

Na początku zadania zapisujemy czas próby, czyścimy błąd i status. Cały eksport jednej tabeli działa w jednej transakcji SQL `SERIALIZABLE`, na zachowanym połączeniu. Dane są czytane bezpośrednio ze źródła; nie tworzymy `#ArchiveDay`. Zakres to pełne dni sprzed północy serwera SQL pomniejszonej o retencję. Tabela musi mieć kolumnę daty i niefiltrowany unikalny klucz, również złożony. Partia używa `ORDER BY` po tym kluczu oraz `OFFSET/FETCH`.

Dane dopisują się do `.csv.tmp`, a nagłówek jest zapisywany raz. Po sprawdzeniu liczby rekordów następuje przemianowanie na `.csv`, zapis `Success` i zatwierdzenie transakcji. Obie daty otrzymują dokładnie tę samą wartość `SYSDATETIME()`. Na błędzie wycofujemy transakcję tabeli, zapisujemy `Error` i szczegóły osobnym połączeniem, zachowując ostatnią datę sukcesu. Kolejne zadania są przetwarzane dalej. Błąd pojedynczej tabeli pojawia się jako ostrzeżenie; końcowe podsumowanie oznacza pakiet jako nieudany, jeżeli były błędy. Brak dostępu do konfiguracji lub niemożność zapisania stanu zatrzymuje pakiet.

Transakcja SQL nie obejmuje systemu plików. Przy obsłużonym błędzie finalizacji opublikowany CSV wraca do `.tmp`. Nagłe zakończenie procesu lub awaria komputera może zostawić nieukończony stan wymagający sprawdzenia. Nowa próba zawsze ma nowy GUID. Blokady źródła trwają przez cały eksport tabeli i mogą blokować równoległe zapisy; limit oczekiwania na blokadę wynosi 30 sekund. Dalsze partie `OFFSET` mogą być wolniejsze. Dane źródłowe nie są usuwane ani modyfikowane.

Format CSV: separator `;`, wszystkie pola w cudzysłowach, podwajanie cudzysłowów, UTF-8 z BOM, nagłówki `Nazwa (typ SQL)`, NULL jako puste pole, formatowanie invariant culture. Zmiana struktury podczas eksportu powoduje błąd.

Biblioteka `Integration Services Project2.Database` utrzymuje model i migracje. Instrukcja migracji bez osobnej aplikacji znajduje się w jej README. Konfiguracja biblioteki pochodzi z `appsettings.json`; połączenie SSIS jest osobnym parametrem pakietu.

Źródła Script Tasks są w `scripts`. Po ich zmianie `tools/Build-Package.ps1` osadza kod i kompiluje skrypty przy użyciu Visual Studio 18 Insiders / SSIS 2025. Samo edytowanie pliku w `scripts` nie aktualizuje osadzonego kodu pakietu.

Weryfikacja:

- `tools/Verify-ArchiveJobsDatabase.ps1`: dziewięć kolumn, typy datetime2 i tekstowy status.
- `tools/Verify-MainExport.ps1`: porównanie najnowszych CSV udanych zadań z każdym rekordem i polem źródła, sprawdzenie stanów błędów.
- `tools/Create-TestDatabase.ps1 -IncludeFailure`: izolowany LocalDB z wieloma tabelami, kluczem złożonym, pustą tabelą i celowo błędnym zadaniem.
- `tools/Verify-JobProcessing.ps1`: kontynuacja po błędzie, wyczyszczenie poprzedniego błędu, zachowanie daty sukcesu; `-RetrySucceeded` sprawdza ponowienie po naprawie konfiguracji.
- `tools/Verify-Export.ps1`: dokładne klucze, retencja, wiele partii, Unicode, cudzysłowy, średniki, wielowierszowy tekst i BOM.

Test LocalDB potwierdził 2506 rekordów Orders, 1002 Events oraz pustą tabelę. Pierwszy przebieg: trzy sukcesy i jeden kontrolowany błąd; po poprawieniu kolumny daty: cztery sukcesy, równe daty i puste ErrorMessage. Osobny test błędu finalizacji potwierdził zachowanie daty sukcesu, wycofanie transakcji i pozostawienie `.tmp`. Wyniki: `verification/20261008_152034`. Ten ostatni kontrolowany błąd pozostaje w izolowanej bazie testowej. Wynik porównania właściwej bazy: `verification/main-export-result.txt`.
