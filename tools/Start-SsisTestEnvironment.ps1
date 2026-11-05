$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'docker/ssis-test'
$envFile=Join-Path $directory '.env'
if(!(Test-Path -LiteralPath $envFile)) {
    $password='Ssis!'+[Guid]::NewGuid().ToString('N')+'a9'
    [IO.File]::WriteAllText($envFile,"SSIS_TEST_SA_PASSWORD=$password`n")
}
$line=Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^SSIS_TEST_SA_PASSWORD=' } | Select-Object -First 1
if(!$line) { throw 'Missing SSIS_TEST_SA_PASSWORD in docker/ssis-test/.env' }
$password=$line.Substring('SSIS_TEST_SA_PASSWORD='.Length)
$compose=Join-Path $directory 'compose.yaml'
& docker compose --env-file $envFile -f $compose up -d --wait --wait-timeout 240
if($LASTEXITCODE -ne 0) { throw 'Docker Compose startup failed.' }
$container=& docker compose --env-file $envFile -f $compose ps -q sql
if($LASTEXITCODE -ne 0 -or !$container) { throw 'SQL container not found.' }
& docker cp (Join-Path $directory 'Seed.sql') "${container}:/tmp/ssis-seed.sql"
if($LASTEXITCODE -ne 0) { throw 'Copying seed failed.' }
& docker exec $container sh -c '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -f 65001 -i /tmp/ssis-seed.sql'
if($LASTEXITCODE -ne 0) { throw 'SQL seed failed.' }
$archiveRoot=Join-Path $directory 'archives'
$existingConfig=Join-Path $directory 'ssis.local.json'
if(Test-Path -LiteralPath $existingConfig) {
    $previous=Get-Content -LiteralPath $existingConfig -Raw | ConvertFrom-Json
    if($previous.ArchiveRoot) { $archiveRoot=$previous.ArchiveRoot }
}
[void](New-Item -ItemType Directory -Path $archiveRoot -Force)
$config=[ordered]@{
    ConnectionString="Data Source=tcp:127.0.0.1,14422;User ID=sa;Password=$password;Initial Catalog=SsisArchiveTest;TrustServerCertificate=True"
    ArchiveJobsTable='SsisArchiveTest.Archive.ArchiveJobs'
    ArchiveRoot=$archiveRoot
    MaxRecordsPerCsv=1000
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'ssis.local.json') -Encoding UTF8
Write-Output 'SQL Server ready: 127.0.0.1,14422 / SsisArchiveTest / SQL login: sa'
Write-Output 'Password: docker/ssis-test/.env; SSIS parameters: docker/ssis-test/ssis.local.json'
