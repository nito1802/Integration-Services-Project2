param([Parameter(Mandatory=$true)][string]$SetupPath)
$ErrorActionPreference='Stop'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script as Administrator to install the isolated test instance.' }
$root=Split-Path $PSScriptRoot -Parent
$evidence=Join-Path $root 'artifacts/sql2022'
[void](New-Item -ItemType Directory -Path $evidence -Force)
$account=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments=@('/Q','/ACTION=Install','/FEATURES=SQLENGINE,IS','/INSTANCENAME=SSISARCHIVE22',
 '/IACCEPTSQLSERVERLICENSETERMS','/UPDATEENABLED=False','/SUPPRESSPRIVACYSTATEMENTNOTICE','/SUPPRESSPAIDEDITIONNOTICE',
 ('/SQLSYSADMINACCOUNTS="'+$account+'"'),'/AGTSVCSTARTUPTYPE=Automatic','/SQLSVCSTARTUPTYPE=Automatic',
 '/TCPENABLED=0','/NPENABLED=0','/SQLMAXMEMORY=1024','/SQLTEMPDBFILECOUNT=1')
$process=Start-Process -FilePath $SetupPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
('Setup exit: '+$process.ExitCode) | Set-Content (Join-Path $evidence 'setup-result.txt')
if($process.ExitCode -notin @(0,3010)) { throw "SQL setup failed: $($process.ExitCode). See SQL Server Setup Bootstrap logs." }
Get-Service -Name 'MSSQL$SSISARCHIVE22','SQLAgent$SSISARCHIVE22','MsDtsServer160' | Select-Object Name,Status | Out-String | Set-Content (Join-Path $evidence 'services.txt')
