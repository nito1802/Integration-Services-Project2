param([switch]$Retry,[switch]$FullPackage,[ValidateSet('None','Write','Delete')][string]$FailureMode='None')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB test' }
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS')
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$package=$app.LoadPackage((Join-Path $PSScriptRoot 'compatibility-test.dtsx'),$null)
$package.Parameters['ConnectionString'].Value=$config.ConnectionString
$package.Parameters['ArchiveJobsConnectionString'].Value=$config.ConnectionString
$output=Join-Path $config.RunDirectory $(if($Retry) {'retry-csv'} else {'native-csv'})
$package.Parameters['ArchiveRoot'].Value=$output
foreach($connection in $package.Connections) { $connection.ConnectionString=$config.ConnectionString }
if($FailureMode -eq 'Delete') {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try { $cmd=$db.CreateCommand(); $cmd.CommandText="CREATE TRIGGER dbo.RejectArchiveDelete ON dbo.Orders INSTEAD OF DELETE AS THROW 50002,'Injected delete failure.',1;"; [void]$cmd.ExecuteNonQuery() } finally { $db.Dispose() }
}
if($FullPackage) {
    $result=$package.Execute()
} else {
    # The installed runtime can execute tasks but is not licensed to schedule an entire package.
    # Exercise the real TaskHost objects and parameter/result bindings in control-flow order.
    $legacy=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Verify-DeleteExport.ps1') -Raw
    $stub=[regex]::Match($legacy,'(?s)\$stub=@"\r?\n(.*?)\r?\n"@').Groups[1].Value
    $build=Join-Path $PSScriptRoot '.script-build/native-sql-test'
    [void](New-Item -ItemType Directory -Path $build -Force)
    $stubPath=Join-Path $build 'Stub.cs'; [IO.File]::WriteAllText($stubPath,$stub)
    $files=@($stubPath)
    $common=Get-Content -LiteralPath (Join-Path $root 'scripts/Common.cs') -Raw
    $names=@('Prepare archive job','BeginScript','GetGuid','Get DateTo','Construct SQL','Export data to CSV','Prepare batch delete','Stage batch keys','Check deleted rows','Report archive job')
    for($i=0;$i -lt $names.Count;$i++) {
        $main=Get-Content -LiteralPath (Join-Path $root ('scripts/'+$names[$i]+'.cs')) -Raw
        if($FailureMode -eq 'Write' -and $names[$i] -eq 'Export data to CSV') {
            $main=$main.Replace('writer.WriteLine();','writer.WriteLine(); if (Convert.ToString(Dts.Variables["User::TableName"].Value) == "dbo.Orders") throw new IOException("Injected write failure.");')
        }
        $file=Join-Path $build ('Step'+$i+'.cs')
        [IO.File]::WriteAllText($file,$common.Replace('__NAMESPACE__',('NativeProbe'+$i)).Replace('// __MAIN__',$main)); $files+=$file
    }
    $dll=Join-Path $build 'NativeProbe.dll'
    & 'C:/Program Files/Microsoft Visual Studio/18/Insiders/MSBuild/Current/Bin/Roslyn/csc.exe' /nologo /target:library "/out:$dll" /reference:System.Data.dll $files
    if($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
    Add-Type -Path $dll
    $probe=New-Object ProbeDts
    foreach($connectionName in @('ArchiveDb','ArchiveJobsDb')) {
        $connection=New-Object ProbeConnection
        $connection.Connection=$package.Connections[$connectionName].AcquireConnection($null)
        $probe.Connections.Add($connectionName,$connection)
    }
    function Step($container,$name) {
        $task=$container.Executables[$name]
        if($task.GetExpression('Disable') -and $package.Variables['User::JobFailed'].Value) { return }
        $index=[Array]::IndexOf($names,$name)
        if($index -ge 0) {
            $probe.Variables.Clear()
            foreach($variable in $package.Variables) { $v=New-Object ProbeVariable; $v.Value=$variable.Value; $probe.Variables.Add($variable.QualifiedName,$v) }
            $probe.Variables['$Package::ArchiveRoot'].Value=$output
            $script=New-Object ('NativeProbe'+$index+'.ScriptMain'); $script.Dts=$probe; $script.Main()
            foreach($variable in $package.Variables) { if($variable.Namespace -eq 'User') { $variable.Value=$probe.Variables[$variable.QualifiedName].Value } }
            return
        }
        $before=$package.Errors.Count
        $result=$task.Execute($package.Connections,$task.Variables,$null,$null,$null)
        $errors=@($package.Errors | Select-Object -Skip $before | ForEach-Object Description)
        if($result -ne 'Success' -or $errors.Count -gt 0) {
            if($name -in @('Count days diff','Read archive batch','Create batch key table','Delete exported batch')) {
                # TaskHost.Execute does not dispatch the package scheduler's event handlers.
                $package.Variables['User::JobFailed'].Value=$true
                $package.Variables['User::JobError'].Value=$errors -join [Environment]::NewLine
            } else { throw "Task $name failed: $($errors -join '; ')" }
        }
    }
    Step $package 'Get Archive Jobs'
    $jobs=$package.Variables['User::Tables'].Value.Tables[0].Copy()
    $tables=$package.Executables['Foreach Loop Container']
    $days=$tables.Executables['For Loop Container']
    $batches=$days.Executables['Loop through 1000']
    foreach($job in $jobs.Rows) {
        foreach($entry in @(@('ArchiveJobId','Id'),@('DatabaseName','DatabaseName'),@('TableName','TableName'),@('Days','ArchiveOlderThanDays'),@('ColumnDate','DateColumn'))) {
            $package.Variables['User::'+$entry[0]].Value=$job[$entry[1]]
        }
        foreach($name in @('Start archive job','Prepare archive job','BeginScript','Count days diff','GetGuid')) { Step $tables $name }
        $package.Variables['User::LoopCounter'].Value=[int]0
        while(!$package.Variables['User::JobFailed'].Value -and $package.Variables['User::LoopCounter'].Value -lt $package.Variables['User::DaysCounter'].Value) {
            Step $days 'Get DateTo'
            while(!$package.Variables['User::JobFailed'].Value -and $package.Variables['User::BatchHasRows'].Value) {
                foreach($name in @('Construct SQL','Read archive batch','Export data to CSV','Prepare batch delete','Create batch key table','Stage batch keys','Delete exported batch','Check deleted rows')) { Step $batches $name }
            }
            $package.Variables['User::LoopCounter'].Value=[int]($package.Variables['User::LoopCounter'].Value+1)
        }
        foreach($name in @('SetTableStatus','Report archive job')) { Step $tables $name }
    }
    $result='Individual native tasks completed (scheduler not exercised)'
}
$messages=@($package.Errors | ForEach-Object Description)
$messages | Set-Content -LiteralPath (Join-Path $config.RunDirectory 'native-errors.txt')
Write-Output "Package result: $result"
$messages | Write-Output
$db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
$db.Open()
try {
    $cmd=$db.CreateCommand()
    $cmd.CommandText='SELECT Id,LastProcessedStatus,ErrorMessage FROM Archive.ArchiveJobs ORDER BY Id;'
    $table=New-Object Data.DataTable
    $table.Load($cmd.ExecuteReader())
    $table | Format-Table -AutoSize | Out-String | Write-Output
    $successful=if($FailureMode -eq 'None') {@(1,3,4)} else {@(3,4)}
    foreach($id in $successful) {
        $job=@($table.Rows | Where-Object Id -eq $id)[0]
        if($job.LastProcessedStatus -ne 'Success') { throw "Job $id did not succeed" }
    }
    if(@($table.Rows | Where-Object Id -eq 2)[0].LastProcessedStatus -ne 'Error') { throw 'Expected SQL range failure' }
    if($FailureMode -ne 'None' -and @($table.Rows | Where-Object Id -eq 1)[0].LastProcessedStatus -ne 'Error') { throw 'Expected injected failure' }
    $cmd.CommandText='SELECT (SELECT COUNT(*) FROM dbo.Orders)+(SELECT COUNT(*) FROM audit.Events);'
    $sourceExpected=if($FailureMode -eq 'None') {3} else {2509}
    if($cmd.ExecuteScalar() -ne $sourceExpected) { throw 'Unexpected source rows after deletion' }
    $files=@(Get-ChildItem -LiteralPath $output -Filter '*.csv' -Recurse)
    $rowCount=0
    foreach($file in $files) { $rowCount+=@(Import-Csv -LiteralPath $file.FullName -Delimiter ';').Count }
    $expected=if($Retry) {0} elseif($FailureMode -eq 'Write') {1003} elseif($FailureMode -eq 'Delete') {2002} else {3508}
    if($rowCount -ne $expected) { throw "Unexpected CSV rows: $rowCount, expected $expected" }
    if($files.Count -ne 3) { throw "Expected three successful CSV files, got $($files.Count)" }
    $cmd.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobs WHERE LastProcessedStatus=N'Error' AND LastSuccesProcessedAt='2025-01-01';"
    $failedExpected=if($FailureMode -eq 'None') {1} else {2}
    if($cmd.ExecuteScalar() -ne $failedExpected) { throw 'Previous success date was overwritten on failure' }
    "PASS: native Execute SQL Tasks; mode=$FailureMode; CSV rows=$rowCount; source rows=$sourceExpected; SQL error persisted; following jobs succeeded; previous success date preserved. Scheduler/event-handler execution requires SSDT." | Tee-Object -FilePath (Join-Path $config.RunDirectory $(if($Retry) {'native-retry-result.txt'} else {'native-result.txt'}))
} finally { $db.Dispose() }
