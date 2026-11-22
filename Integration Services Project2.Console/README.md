# Wspólny seed testów archiwizacji

Uruchom projekt bez argumentów albo przez F5 w Visual Studio:

```powershell
dotnet run --project "Integration Services Project2.Console"
```

Program wykonuje jedną metodę `TestDataSeeder.SeedAsync()`. Połączenie pochodzi
z `ConnectionStrings:ArchiveJobsDatabase`. Konfiguracja zadań i relacji znajduje
się w `nito_superDb.Archive`, a tabele źródłowe w bazach `nito_superDb`
i `nito_SomeApps` na tym samym serwerze. Obie bazy muszą istnieć.

## Dane tworzone w każdej bazie

| Obiekt | Liczba |
|---|---:|
| Zadania dla tabel głównych Root01–Root40 | 40 |
| Relacje | 25 |
| Tabele główne i zależne w ArchiveScenarioTest | 64 |
| Rekordy danych testowych | 189 |

Łącznie seed utrzymuje 80 własnych zadań i 50 własnych relacji.
Wcześniejsze zadania oraz inne schematy zachowują swoje dane.
Dlatego całkowita liczba wpisów konfiguracji może być większa.

## Scenariusze

- Root01 ma dziecko z relacją jeden-do-wielu.
- Root02 ma dziecko i wnuki.
- Root03 tworzy łańcuch czterech tabel.
- Root04 ma trzy tabele dzieci.
- Root05 rozgałęzia się na Left i Right, które wskazują wspólne Shared.
  Rekord Shared pasujący przez obie relacje jest eksportowany raz.
- Root06 tworzy łańcuch pięciu tabel.
- Root07 ma dwie gałęzie z kolejnymi dziećmi.
- Root08 ma trzy tabele dzieci.
- Root09–Root38 to samodzielne tabele z datą.
- Root39 zawiera wyłącznie świeże rekordy.
- Root40 pozostaje pusta.

Retencja wynosi 30 dni. Zwykły rodzic ma rekordy sprzed 60 i 59 dni oraz
jeden dzisiejszy. Dzieci mają po dwa rekordy wskazujące starego rodzica
i jeden wskazujący świeżego. Tabele zależne nie mają dat.
Wszystkie FK mają ON DELETE NO ACTION, a kolumny FK są indeksowane.

Po poprawnej archiwizacji z każdej bazy powinny zostać wyeksportowane
124 rekordy, a w źródle pozostać 65 rekordów. Każda baza ma identyczne
nazwy tabel i klucze, co pozwala sprawdzić rozdzielenie danych po DatabaseName.

## Konfiguracja i ponowienie

ArchiveJobRelations przechowuje DatabaseName, ArchiveJobId, ParentTable,
ChildTable, ParentKeyColumn i ChildKeyColumn. Nazwy tabel mają format
schema.Tabela. Pakiet pobiera relacje pasujące do Id zadania oraz jego DatabaseName.
Kolumna DatabaseName istniejących relacji jest uzupełniana na podstawie ArchiveJobs.
Parametr pakietu ArchiveJobRelationsTable wskazuje tabelę relacji niezależnie
od ArchiveJobsTable. Przyjmuje schema.Tabela albo baza.schema.Tabela.
Domyślna wartość w projekcie to nito_superDb.Archive.ArchiveJobRelations.

Uruchamiaj seed przy zatrzymanym pakiecie. Ponowienie odtwarza dane
ArchiveScenarioTest w obu bazach, resetuje statusy jego zadań i odtwarza
jego relacje. Identyfikatory zadań pozostają stabilne.
Odtworzenie obu baz i konfiguracji wykonuje się w jednej transakcji.
Aktualizacja struktury ArchiveJobRelations poprzedza tę transakcję.

## Weryfikacja w izolowanych bazach

```powershell
powershell -NoProfile -File tools/Create-TestDatabase.ps1
powershell -NoProfile -File tools/Build-Package.ps1 -CompatibilityTest
powershell -NoProfile -File tools/Verify-SqlTasks.ps1 -MultiDatabase
```

Test wykonuje rzeczywiste zadania SQL i kod skryptów pakietu na dwóch LocalDB,
sprawdza 80 statusów Success, zawartość ZIP-ów, brak powtórzonych kluczy
oraz liczbę rekordów pozostałych w obu bazach.
