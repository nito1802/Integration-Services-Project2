# Wydanie dla SQL Server 2022

Aktualny job `SSIS Archive SQL2022 Test 20261106_153717` zostal przelaczony na natywny krok typu **SQL Server Integration Services Package** (`SSIS`). Zachowano cztery parametry pakietu i pojedynczy krok. Konwersje wykonuje `tools/Set-Sql2022TestJobSsisStep.ps1`; kopia poprzedniego T-SQL jest w `artifacts/sql2022/job-step-before-ssis.local.json`. Test natywnego kroku: Success, wykonanie SSISDB nr 8. W SSMS parametry sa dostepne w Job Properties -> Steps -> Edit -> Configuration -> Parameters; obok jest Connection Managers. SSMS 22 wymaga komponentu `Microsoft.SSMS.Component.IS` (Integration Services management capabilities), dostepnego w Visual Studio Installer.

Aktualizacja 2026-11-06: usunieto connection manager `ArchiveJobsDb`. Wszystkie kroki SQL (odczyt konfiguracji, archiwizacja i zapis statusow) uzywaja jednego `ArchiveDb`, sterowanego parametrem pakietu `ConnectionString`, z zachowaniem sesji dla `#ArchiveDay`. Potwierdzono pelnym jobem SQL Agent `SSIS Archive SQL2022 Test 20261106_153717`, wykonanie SSISDB nr 7: Success, bez ostrzezen i bledow. Swieza baza: `SsisArchiveTest2022_20261106_153717`; archiwa: `C:\ArchiveTest\Sql2022_20261106_153717`. Wynik: 5 ZIP, 13 CSV, 9502 rekordy; w zrodle pozostaly 2 zamowienia i 1 zdarzenie.

Projekt domyslnie celuje w SQL Server 2022. Wszystkie 32 Script Tasks maja VSTA 16 oraz binarne referencje do ManagedDTS i ScriptTask 16.0.0.0. Zmiana obejmuje rowniez osadzone projekty C# (referencje i SSIS_ST160), a nie tylko atrybut wersji w XML.

## Budowanie

Uruchom z Windows PowerShell 5.1 w katalogu solucji:

```powershell
./tools/Build-Package.ps1 -TargetServerVersion SQLServer2022
./tools/Build-Sql2022Ispac.ps1
./tools/Verify-Sql2022Ispac.ps1
```

Wymagane sa zainstalowane narzedzia SSIS Projects z targetem 2022. Skrypty korzystaja z lokalnej instalacji Visual Studio 18 Insiders. `Build-Sql2022Ispac.ps1 -VisualStudioRoot` pozwala wskazac katalog Visual Studio uzywany do budowania ISPAC. Generator przeplywu `Build-Package.ps1` korzysta z lokalnego runtime ManagedDTS i kompilatora w Visual Studio 18 Insiders.

Wynik: `artifacts/sql2022/Archive.Sql2022.ispac`, nazwa projektu w SSISDB: `Archive.Sql2022`, pakiet: `Package.dtsx`. Domyslne parametry wydania nie zawieraja hasel ani polaczen produkcyjnych. Przy wdrozeniu ustaw `ConnectionString`, `ArchiveJobsTable`, `ArchiveRoot` i `MaxRecordsPerCsv`. Wymagany 7-Zip pod `C:\Program Files\7-Zip\7z.exe` oraz zapis do katalogu archiwum dla konta wykonujacego pakiet. Folder musi znajdowac sie na maszynie wykonujacej SSIS lub byc dostepna sciezka UNC.

Samo polaczenie z baza SQL Server 2022 nie potwierdza kompatybilnosci runtime. Paczka musi wykonac sie w SSIS 2022.

## Test SQL Server Agent 2026-11-05

Zainstalowano lokalna instancje SQL Server 2022 Developer `.\SSISARCHIVE22` wraz z SSIS 2022 i SQL Server Agent. Instancja korzysta z Windows Authentication; TCP i named pipes pozostaja wylaczone. Test uruchamia pelny pakiet z SSISDB, bez projektanta i bez zastepczego hosta skryptow.

`tools/Deploy-Sql2022TestJob.ps1` tworzy swieza baze i dane z `docker/ssis-test/Seed.sql`, wdraza dokladnie gotowy ISPAC oraz tworzy i uruchamia rzeczywisty job SQL Agenta. Krok typu T-SQL wywoluje `SSISDB.catalog.create_execution`, ustawia parametry i uruchamia pakiet synchronicznie. Status inny niz 7 powoduje blad joba. Job nie ma cyklicznego harmonogramu.

```powershell
./tools/Deploy-Sql2022TestJob.ps1
./tools/Get-Sql2022TestJobResult.ps1
./tools/Verify-DockerArchiveTest.ps1 -ConfigPath artifacts/sql2022/test.local.json -ReportPath artifacts/sql2022/archive-verification.txt
```

Ostatni zakonczony test: job `SSIS Archive SQL2022 Test 20261105_095931`, baza `SsisArchiveTest2022_20261105_095931`, archiwa `C:\ArchiveTest\Sql2022_20261105_095931`. Poprzednie pliki testowe zachowano.

Wynik: 3 zadania Success, 5 ZIP-ow, 13 CSV, 7500 zamowien i 2002 zdarzenia zarchiwizowane. W bazie pozostaly 2 zamowienia i 1 zdarzenie; brak kwalifikujacych sie starych danych. Sprawdzono integralnosc ZIP, unikalnosc i kompletnosc kluczy, wartosci pol, UTF-8, polskie znaki, NULL, wielowierszowy tekst, podzial na dni i partie do 1000 rekordow oraz usuniecie roboczych CSV.

Pierwszy seed uruchomiony w PowerShell 5.1 odczytal polskie znaki z niewlasciwym kodowaniem. Poprawiono odczyt Seed.sql na jawne UTF-8 i powtorzono caly test na nowej bazie. Nie byl to blad zapisu danych przez pakiet.

Dowody w `artifacts/sql2022`: `compatibility.txt`, `build.log`, `job-result.txt`, `archive-verification.txt`. `test.local.json` przechowuje parametry ostatniego testu. `catalog-key.local.txt` to zaszyfrowane przez Windows DPAPI haslo klucza lokalnego SSISDB. Artefakty lokalne sa ignorowane w Git. Zadania i bazy testowe pozostaja dostepne do inspekcji w SSMS.
