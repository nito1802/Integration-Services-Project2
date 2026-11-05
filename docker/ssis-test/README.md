# Lokalne testy archiwizacji

Z katalogu solucji: `./tools/Start-SsisTestEnvironment.ps1`.

SQL Server 2022 Developer jest dostepny w SSMS pod `127.0.0.1,14422`, SQL Server Authentication, login `sa`. Haslo jest generowane w lokalnym `.env`. Baza: `SsisArchiveTest`.

Parametry pakietu SSIS sa zapisane w `ssis.local.json` (lokalny plik z haslem). Ustaw je w oknie wykonania pakietu w Visual Studio. Skrypt nie zmienia polaczen istniejacego pakietu ani aplikacji. Archiwa trafiaja do `docker/ssis-test/archives` na Windowsie; wymagany 7-Zip pod sciezka skonfigurowana w pakiecie.

| Tabela | Wiersze na starcie | Do archiwizacji przy retencji 30 dni |
|---|---:|---:|
| Demo.Orders | 7502 | 7500, trzy dni po 2500 (3 CSV na dzien) |
| Demo.Events | 2003 | 2002, dwa oddalone dni po 1001 (2 CSV na dzien), klucz zlozony |
| Demo.EmptyTable | 0 | 0 |

`Archive.ArchiveJobs` zawiera trzy odpowiadajace zadania. Po udanym wykonaniu powinny pozostac 2 zamowienia i 1 zdarzenie; statusy zadan powinny wynosic `Success`. Dane sa tworzone tylko przy pierwszym utworzeniu tabeli. Ponowne uruchomienie skryptu zachowuje dane i statusy. Wolumen Docker zachowuje baze po odtworzeniu kontenera.

Zatrzymanie: `docker compose -f docker/ssis-test/compose.yaml --env-file docker/ssis-test/.env stop`.

Kontener sluzy do testowania bazy. Pakiet SSIS wykonuje sie na Windowsie. Wlaczony SQL Agent w kontenerze nie stanowi srodowiska do testowania windowsowego kroku SSIS. Wersja silnika zrodlowego SQL nie wymaga obnizenia TargetServerVersion pakietu.

## Wykonany test 2026-11-02

Pelny pakiet uruchomiono przez F5 w Visual Studio/SSDT na odizolowanej kopii `designer-test/DockerArchiveTest.dtproj`. Lokalny `ssis.local.json` wskazuje `C:\ArchiveTest`; ponowny start srodowiska zachowuje te sciezke. Bezposrednie uruchomienie przez ManagedDTS 2025 nie bylo mozliwe z powodu brakujacej zarejestrowanej klasy runtime; debugger SSDT wykonal pakiet poprawnie.

Wynik: wszystkie trzy zadania `Success`, 5 ZIP-ow, 13 CSV wewnatrz ZIP-ow, 9502 zarchiwizowane rekordy. W bazie pozostaly 2 zamowienia i 1 zdarzenie. Nie pozostaly robocze CSV. Uruchomienie `./tools/Verify-DockerArchiveTest.ps1` weryfikuje statusy, integralnosc ZIP, dane CSV i rekordy pozostale w bazie. Log wykonania: `verification/docker-archive-ssis-output.txt`; raport kontroli: `verification/docker-archive-results.txt`.

Nie utworzono joba SQL Server Agent; ten test weryfikuje pelny pakiet wykonany na Windowsie z baza SQL Server 2022 w Dockerze. Kopia projektanta jest lokalna i ignorowana w Git, poniewaz zawiera dane polaczenia. Pierwsze F5 moze tylko zbudowac projekt; otworz `Package.dtsx`, poczekaj na zaladowanie projektanta i uruchom F5. Po wykonanym tescie ponowne uruchomienie nie odtworzy usunietych danych.
