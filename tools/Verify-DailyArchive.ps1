$ErrorActionPreference='Stop'
function Fresh {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Create-TestDatabase.ps1') -IncludeFailure
    if($LASTEXITCODE -ne 0) { throw 'Fixture creation failed' }
}
function Verify {
    param([string[]]$TestArguments=@())
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-SqlTasks.ps1') @TestArguments
    if($LASTEXITCODE -ne 0) { throw 'Daily archive verification failed' }
}
Fresh
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Verify-ConnectionRouting.ps1')
if($LASTEXITCODE -ne 0) { throw 'Connection routing verification failed' }
Verify
Verify -TestArguments @('-Retry')
Fresh
Verify -TestArguments @('-SpreadDates','-MaxRecordsPerCsv','37')
Fresh
Verify -TestArguments @('-KeyTypes')
foreach($mode in @('Read','Write','Delete','Zip','ZipTest','FolderCollision','ZipCollision')) {
    Fresh
    Verify -TestArguments @('-FailureMode',$mode)
}
Write-Output 'PASS: daily CSV/ZIP suite'
