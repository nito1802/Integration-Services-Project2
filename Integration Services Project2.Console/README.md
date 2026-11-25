# Seed GenericSignature

Uruchom Console bez argumentów lub przez F5:

```powershell
dotnet run --project "Integration Services Project2.Console"
```

Domyślnie Program.cs uruchamia TestDataSeeder.LittleSeedAsync(). Pełny zestaw
można odtworzyć przez zmianę wywołania na TestDataSeeder.SeedAsync(). Obie metody
korzystają ze wspólnego modelu, konfiguracji i generatora relacji. Połączenie pochodzi z
ConnectionStrings:ArchiveJobsDatabase w appsettings.json projektu Database.
Źródła powstają w nito_superDb i nito_SomeApps na tym samym serwerze.
Konfiguracja pozostaje w nito_superDb.Archive.

Każda baza otrzymuje schemat GenericSignatureTest: Processes,
AutentiProcesses, AutentiRecipients, CallProcesses, ProcessData,
EkdProcesses, EkdProcessHistories, ExportLoadTest oraz słowniki ProcessTypes i EkdStatuses.
Model EF jest w katalogu GenericSignature w Console. Pola, długości, nullable
i relacje odtworzono ze zdjęć. Definicji słowników nie było na zdjęciach:
przyjęto Id i Name. Enumy Autenti mają testowe wartości 0–3. Dla EnvelopeId
przyjęto ograniczenie klucza EF do 450 znaków. AutentiRecipients ma klucz
złożony EnvelopeId + Email; RecipientId jest osobnym polem.

Pełny SeedAsync obejmuje 2023-01-01 do dnia uruchomienia. Około 95,7% dni zawiera dane:
zwykle 1–9 procesów, okresowo 35, co 23 dni jeden dzień jest pusty.
Procesy mają 0–2 rekordy Autenti i Ekd, odbiorców, historie, opcjonalne
CallProcesses i 1–4 ProcessData. Dane są syntetyczne; adresy używają
example.invalid. Rozkład dat i liczby są powtarzalne, GUID-y są nowe.
Indeksy obejmują CreationDate i klucze obce.

LittleSeedAsync zastępuje dane w tych samych tabelach małym zestawem:
3 i 5 stycznia, 7 i 9 marca oraz 12 i 14 czerwca zarówno 2023, jak i 2024 roku.
W kolejnych sześciu dniach każdego roku jest 3, 4, 5, 6, 3 i 4 procesy
(25 na rok, łącznie 50 na bazę), z pełnym drzewem zależności.
Nie pozostawia danych z pełnego seeda. Wszystkie dwanaście dni kwalifikuje się do
archiwizacji; pakiet może pomijać przerwy między miesiącami. Pliki archiwów
z wcześniejszych uruchomień pozostają zachowane.

W ArchiveJobs powstają dwa joby na bazę. Pierwszy: GenericSignatureTest.Processes,
CreationDate, retencja 30 dni. Sześć relacji na bazę obejmuje drzewo:

- Processes → AutentiProcesses → AutentiRecipients
- Processes → EkdProcesses → EkdProcessHistories
- Processes → CallProcesses
- Processes → ProcessData

Słowniki pozostają w źródle. Ponowienie usuwa dane GenericSignatureTest,
zasila je od nowa, resetuje statusy jego jobów i odtwarza relacje.
Id jobów pozostają stabilne. Usuwane są też stare tabele i schemat
ArchiveScenarioTest oraz ich wpisy Jobs/Relations. Inne schematy, zadania
i pliki archiwów pozostają zachowane. Uruchamiaj przy zatrzymanym pakiecie.

Każda baza wraz ze swoją konfiguracją ma osobną transakcję. Przy błędzie
drugiej bazy pierwsza może być już zatwierdzona; ponowienie odtwarza obie.
Seeder uruchamia wyłącznie migrację relacji z CreateArchiveJobRelations.sql,
pomijając dopisane pod nią ręczne przykłady i zapytania diagnostyczne.

Stare scenariusze są wyłącznie fixture w tools/ArchiveScenarioFixture.sql
na potrzeby istniejących testów regresyjnych SSIS. Console ich nie uruchamia.

Weryfikacja zasianych danych (tylko odczyt):

```powershell
powershell -NoProfile -File tools/Verify-GenericSignatureSeed.ps1
```

Dla małego zestawu dodaj przełącznik `-Little`.


ExportLoadTest to niezależna tabela do dłuższego eksportu, bez relacji z Processes.
Zarówno SeedAsync, jak i LittleSeedAsync wstawiają po 100 000 rekordów w każdej bazie:
CreatedAt z 14 czerwca 2024, Payload długości 64 znaków. To około 10 MB CSV,
100 paczek przy MaxRecordsPerCsv=1000. Drugim jobem jest GenericSignatureTest.ExportLoadTest
z kolumną daty CreatedAt i retencją 30 dni. Ponowienie seeda resetuje również ten job
oraz odtwarza wszystkie jego rekordy. Krótszy payload ogranicza zajętość bazy hostingowej.