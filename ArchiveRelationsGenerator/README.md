# Generator INSERT-ów relacji — WPF

Otwórz `ArchiveRelationsGenerator.sln`, ustaw projekt `.Wpf` jako startowy i naciśnij F5.
Alternatywnie, z katalogu repozytorium:

```powershell
dotnet run --project ArchiveRelationsGenerator/ArchiveRelationsGenerator.Wpf
```

1. W SSMS wykonaj zapytanie o zależności FK.
2. Zaznacz wiersze w Results, wybierz **Copy with Headers** i wklej do aplikacji.
3. Podaj nazwę bazy źródłowej, np. `nito_superDb` lub `360_genericsignature_dev01`.
4. Wybierz **Generuj INSERT**. Otworzy się osobne okno z zaznaczalnym SQL-em,
   przyciskiem **Kopiuj SQL** i znikającym komunikatem potwierdzającym kopiowanie.

Program generuje INSERT do `Archive.ArchiveJobRelations`; nie łączy się z SQL Serverem.
SQL należy samodzielnie wykonać w bazie zawierającej konfigurację archiwizacji.
Wklejaj **wynik zapytania**, nie jego kod — sam kod nie zawiera danych o FK.
Przycisk **Wczytaj przykład** pokazuje sześć relacji z GenericSignatureTest.

Obsługiwane dane: standardowy wynik dziesięciu kolumn z zapytania (z nagłówkami
lub bez), opcjonalny numer wiersza, albo cztery kolumny ParentTable,
ParentKeyColumn, ChildTable, ChildKeyColumn. Nagłówki umożliwiają dowolną kolejność
kolumn. Najpewniejszy format to tabulatory ze schowka SSMS; obsługiwane są również
kolumny oddzielone co najmniej dwiema spacjami.

Generator normalizuje `[schema].[Tabela]` do `schema.Tabela`, zabezpiecza apostrofy
w literałach SQL, pomija duplikaty i dzieli INSERT-y na partie po 1000 wierszy.
Odrzuca cykle, wyłączone FK i złożone klucze obce: obecna tabela konfiguracji
nie obsługuje kilku par kolumn jako jednego warunku AND. Nazwy zawierające kropkę
wewnątrz identyfikatora również nie są obsługiwane przez format schema.Tabela.
Ponowne wykonanie wygenerowanego INSERT-a nie jest automatycznym UPSERT-em.

Sprawdzenie parsera/generatora bez zewnętrznych pakietów testowych:

```powershell
dotnet run --project ArchiveRelationsGenerator/ArchiveRelationsGenerator.Checks
```
