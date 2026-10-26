param([string]$JobsTable='Archive.ArchiveJobs',[switch]$InsertAfterSnapshot,[switch]$Ssis2025,[switch]$KeyTypes,[switch]$NativeProcessTasks,[switch]$Retry,[switch]$FullPackage,[switch]$SpreadDates,[ValidateSet('None','NullKey','Stage','Read','Write','Delete','Zip','ZipTest','FolderCollision','ZipCollision')][string]$FailureMode='None',[int]$MaxRecordsPerCsv=1000)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB test' }
if($Ssis2025) { [void][Reflection.Assembly]::LoadFrom('C:/Program Files/Microsoft Visual Studio/18/Insiders/Common7/IDE/PublicAssemblies/SSIS/170/Microsoft.SqlServer.ManagedDTS.dll') } else { [void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS') }
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$packagePath=if($Ssis2025) { Join-Path $root 'Integration Services Project2/Package.dtsx' } else { Join-Path $PSScriptRoot 'compatibility-test.dtsx' }
$package=$app.LoadPackage($packagePath,$null)
$package.Parameters['ConnectionString'].Value=$config.ConnectionString
$package.Parameters['ArchiveJobsTable'].Value=$JobsTable
$output=Join-Path $config.RunDirectory $(if($Retry) {'retry-csv'} else {'native-csv'})
[void](New-Item -ItemType Directory -Path $output -Force)
$package.Parameters['ArchiveRoot'].Value=$output
$package.Parameters['MaxRecordsPerCsv'].Value=$MaxRecordsPerCsv
foreach($connection in $package.Connections) { $connection.ConnectionString=$config.ConnectionString }
$package.Connections['ArchiveDb'].ConnectionString=$sourceConnection.ConnectionString
if($SpreadDates -and !$Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try { $cmd=$db.CreateCommand(); $cmd.CommandText='UPDATE dbo.Orders SET CreatedAt=DATEADD(day,-3-CONVERT(int,OrderNo%20),CONVERT(date,GETDATE())) WHERE OrderNo<=2505;'; [void]$cmd.ExecuteNonQuery() } finally { $db.Dispose() }
}
if($KeyTypes -and !$Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand(); $cmd.CommandText=@'
ALTER TABLE audit.Events DROP CONSTRAINT PK_Events;
ALTER TABLE audit.Events ADD Token uniqueidentifier NOT NULL DEFAULT NEWID(), BinaryKey varbinary(16) NOT NULL DEFAULT 0x00FF,
 AmountKey decimal(19,4) NOT NULL DEFAULT 123.4567, DateKey datetime NOT NULL DEFAULT '2020-01-02T12:34:56.123',
 OffsetKey datetimeoffset(7) NOT NULL DEFAULT '2020-01-02T12:34:56.1234567+02:00', TimeKey time(7) NOT NULL DEFAULT '12:34:56.1234567', FloatKey float NOT NULL DEFAULT 1.2345678901234567;
-- next batch
UPDATE audit.Events SET Kind=CASE WHEN SequenceNo%11=0 THEN NCHAR(0)+N'ctrl' WHEN SequenceNo%7=0 THEN N'' ELSE N'Zażółć;"<&' END,
 BinaryKey=CASE WHEN SequenceNo%3=0 THEN 0x ELSE 0x00FF END;
-- next batch
ALTER TABLE audit.Events ADD CONSTRAINT PK_Events PRIMARY KEY (Kind,SequenceNo,Token,BinaryKey,AmountKey,DateKey,OffsetKey,TimeKey,FloatKey);
'@
        foreach($statement in ($cmd.CommandText -split '-- next batch')) { $cmd.CommandText=$statement; [void]$cmd.ExecuteNonQuery() }
    } finally { $db.Dispose() }
}
$batchSizes=@{}
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
    $names=@('Prepare job queries','Initialize job variables','Prepare metadata and date queries','Initialize daily archive','Prepare batch select query','Write batch to CSV','Verify exported day','Verify deleted row count','Log job result','Capture SQL error','Prepare export schema and header','Delete temporary CSV files')
    for($i=0;$i -lt $names.Count;$i++) {
        $main=Get-Content -LiteralPath (Join-Path $root ('scripts/'+$names[$i]+'.cs')) -Raw
        if($FailureMode -eq 'Write' -and $names[$i] -eq 'Write batch to CSV') {
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
    function Step($container,$name) {
        $task=$container.Executables[$name]
        if($task.GetExpression('Disable') -and $package.Variables['User::JobFailed'].Value) { return }
        if($name -in @('Create daily ZIP','Verify ZIP integrity') -and ($package.Variables['User::JobFailed'].Value -or !$package.Variables['User::DayHasFiles'].Value)) { return }
        if($name -in @('Delete archived day','Verify deleted row count') -and !$package.Variables['User::DayHasFiles'].Value) { return }
        $index=[Array]::IndexOf($names,$name)
        if($index -ge 0) {
            $probe.Variables.Clear()
            foreach($variable in $package.Variables) { $v=New-Object ProbeVariable; $v.Value=$variable.Value; $probe.Variables.Add($variable.QualifiedName,$v) }
            foreach($parameter in $package.Parameters) { $key='$Package::'+$parameter.Name; if(!$probe.Variables.ContainsKey($key)) { $probe.Variables.Add($key,(New-Object ProbeVariable)) }; $probe.Variables[$key].Value=$parameter.Value }
            $script=New-Object ('NativeProbe'+$index+'.ScriptMain'); $script.Dts=$probe
            try { $script.Main() }
            catch {
                if($task.EventHandlers.Count -eq 0) { throw }
                # Dispatch the production OnError source through the substitute host.
                $v=New-Object ProbeVariable; $v.Value=$_.Exception.ToString(); $probe.Variables.Add('System::ErrorDescription',$v)
                $v=New-Object ProbeVariable; $v.Value=$true; $probe.Variables.Add('System::Propagate',$v)
                $handler=New-Object ('NativeProbe'+([Array]::IndexOf($names,'Capture SQL error'))+'.ScriptMain')
                $handler.Dts=$probe; $handler.Main()
                if($probe.Variables['System::Propagate'].Value) { throw 'Error handler did not stop propagation' }
            }
            if($FailureMode -eq 'NullKey' -and $name -eq 'Prepare export schema and header' -and $package.Variables['User::ArchiveJobId'].Value -eq 1) {
                $probe.Variables['User::KeyColumns'].Value='OrderNo, Note'
            }
            if($KeyTypes -and $name -eq 'Write batch to CSV' -and !$probe.Variables['User::JobFailed'].Value -and $probe.Variables['User::TableName'].Value -eq 'audit.Events') {
                $data=$probe.Variables['User::BatchData'].Value.Tables[0]
                if($data.Rows.Count -gt 0) {
                    $written=@(Import-Csv -LiteralPath $probe.Variables['User::OutputFile'].Value -Delimiter ';')
                    for($r=0;$r -lt $data.Rows.Count;$r++) {
                        $source=$data.Rows[$r]; $csv=$written[$r]
                        $hex='0x'+[BitConverter]::ToString($source.BinaryKey).Replace('-','')
                        if($csv.'BinaryKey (varbinary)' -ne $hex) { throw 'CSV binary value lost' }
                        if($csv.'DateKey (datetime)' -ne $source.DateKey.ToString('o',[Globalization.CultureInfo]::InvariantCulture)) { throw 'CSV datetime precision lost' }
                        if($csv.'OffsetKey (datetimeoffset)' -ne $source.OffsetKey.ToString('o',[Globalization.CultureInfo]::InvariantCulture)) { throw 'CSV datetimeoffset precision lost' }
                        if($csv.'TimeKey (time)' -ne $source.TimeKey.ToString('c',[Globalization.CultureInfo]::InvariantCulture)) { throw 'CSV time precision lost' }
                        if($csv.'FloatKey (float)' -ne $source.FloatKey.ToString('R',[Globalization.CultureInfo]::InvariantCulture)) { throw 'CSV float precision lost' }
                    }
                }
            }
            foreach($variable in $package.Variables) { if($variable.Namespace -eq 'User') { $variable.Value=$probe.Variables[$variable.QualifiedName].Value } }
            return
        }
        if($name -in @('Create daily ZIP','Verify ZIP integrity')) {
            $dbCheck=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $dbCheck.Open()
            try {
                $check=$dbCheck.CreateCommand()
                $check.CommandText='SELECT COUNT_BIG(*) FROM '+$package.Variables['User::TableName'].Value+' WHERE '+$package.Variables['User::ColumnDate'].Value+' >= @From AND '+$package.Variables['User::ColumnDate'].Value+' < @To;'
                [void]$check.Parameters.AddWithValue('@From',$package.Variables['User::CurrentDateFrom'].Value)
                [void]$check.Parameters.AddWithValue('@To',$package.Variables['User::CurrentDateTo'].Value)
                if([long]$check.ExecuteScalar() -ne ([long]$package.Variables['User::DayRows'].Value + $(if($InsertAfterSnapshot -and $package.Variables['User::ArchiveJobId'].Value -eq 1 -and $package.Variables['User::CurrentDateFrom'].Value -eq $insertedDay) {1} else {0}))) { throw 'Source day was modified/deleted before ZIP verification' }
            } finally { $dbCheck.Dispose() }
            # Exercise the real Execute Process Task. Inject failure via unsupported 7z command.
            $variable=if($name -eq 'Create daily ZIP') {'ZipArguments'} else {'ZipTestArguments'}
            $task.InnerObject.Executable=[string]$package.Parameters['SevenZipPath'].Value
            $task.InnerObject.Arguments=[string]$package.Variables['User::'+$variable].Value
            if($package.Variables['User::ArchiveJobId'].Value -eq 1 -and (($FailureMode -eq 'Zip' -and $name -eq 'Create daily ZIP') -or ($FailureMode -eq 'ZipTest' -and $name -eq 'Verify ZIP integrity'))) {
                $package.Variables['User::'+$variable].Value='invalid-command'
                $task.InnerObject.Arguments='invalid-command'
            }
            if(!$NativeProcessTasks) {
                # Execute Process Task is license-gated outside SSDT on this workstation.
                # Verify its configured executable/arguments using a test-only process host.
                $process=New-Object Diagnostics.Process
                $process.StartInfo.FileName=$task.InnerObject.Executable
                $process.StartInfo.Arguments=$task.InnerObject.Arguments
                $process.StartInfo.UseShellExecute=$false; $process.StartInfo.CreateNoWindow=$true
                $process.StartInfo.RedirectStandardOutput=$true; $process.StartInfo.RedirectStandardError=$true
                try {
                    [void]$process.Start()
                    $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd()
                    $process.WaitForExit()
                    if($process.ExitCode -ne 0) {
                        $package.Variables['User::JobFailed'].Value=$true
                        $package.Variables['User::JobError'].Value="7-Zip exit=$($process.ExitCode): $stderr"
                    }
                } finally { $process.Dispose() }
                return
            }
        }
        if($FailureMode -eq 'Read' -and $name -eq 'Read archive batch' -and $package.Variables['User::ArchiveJobId'].Value -eq 1) {
            $package.Variables['User::SQLStatement'].Value='SELECT MissingArchiveReadColumn FROM #ArchiveDay;'
        }
        if($FailureMode -eq 'Stage' -and $name -eq 'Stage archive day' -and $package.Variables['User::ArchiveJobId'].Value -eq 1) {
            $package.Variables['User::StageDaySql'].Value='SELECT * FROM MissingArchiveStageTable;'
        }
        $before=$package.Errors.Count
        $result=$task.Execute($package.Connections,$task.Variables,$null,$null,$null)
        $errors=@($package.Errors | Select-Object -Skip $before | ForEach-Object Description)
        if($result -ne 'Success' -or $errors.Count -gt 0) {
            if($name -in @('Calculate retention cutoff','Read archive batch','Read column definitions','Read SQL types and keys','Find first archive day','Stage archive day','Drop staged day','Delete archived day','Create daily ZIP','Verify ZIP integrity')) {
                # TaskHost.Execute does not dispatch the package scheduler's event handlers.
                $package.Variables['User::JobFailed'].Value=$true
                $package.Variables['User::JobError'].Value=$errors -join [Environment]::NewLine
            } else { throw "Task $name failed: $($errors -join '; ')" }
        }
        if($name -eq 'Read archive batch' -and !$package.Variables['User::JobFailed'].Value) {
            $id=[int]$package.Variables['User::ArchiveJobId'].Value
            $batchSizes[$id]=@($batchSizes[$id])+@([int]$package.Variables['User::BatchData'].Value.Tables[0].Rows.Count) | Where-Object { $null -ne $_ }
        }
    }
    Step $package 'Prepare job queries'
    Step $package 'Load archive jobs'
    $jobs=$package.Variables['User::Tables'].Value.Tables[0].Copy()
    $tables=$package.Executables['For each archive job']
    $daily=$tables.Executables['For each archive day']
    $batches=$daily.Executables['Process daily batches']
    foreach($job in $jobs.Rows) {
        foreach($entry in @(@('ArchiveJobId','Id'),@('DatabaseName','DatabaseName'),@('TableName','TableName'),@('Days','ArchiveOlderThanDays'),@('ColumnDate','DateColumn'))) {
            $package.Variables['User::'+$entry[0]].Value=$job[$entry[1]]
        }
        foreach($name in @('Mark job as started','Initialize job variables','Prepare metadata and date queries','Read column definitions','Read SQL types and keys','Prepare export schema and header','Calculate retention cutoff','Find first archive day')) { Step $tables $name }
        while(!$package.Variables['User::JobFailed'].Value -and $package.Variables['User::CurrentDateFrom'].Value -lt $package.Variables['User::CutoffDate'].Value) {
            if($package.Variables['User::ArchiveJobId'].Value -eq 1 -and $FailureMode -in @('FolderCollision','ZipCollision')) {
                $day=([datetime]$package.Variables['User::CurrentDateFrom'].Value).ToString('yyyy_MM_dd')
                $year=([datetime]$package.Variables['User::CurrentDateFrom'].Value).ToString('yyyy')
                $months=@('styczen','luty','marzec','kwiecien','maj','czerwiec','lipiec','sierpien','wrzesien','pazdziernik','listopad','grudzien')
                $month=$months[([datetime]$package.Variables['User::CurrentDateFrom'].Value).Month-1]
                $collisionFolder=Join-Path $output "$($config.Database)/dbo.Orders/$year/$month/$day"
                [void](New-Item -ItemType Directory -Path (Split-Path $collisionFolder -Parent) -Force)
                if($FailureMode -eq 'FolderCollision') {
                    [void](New-Item -ItemType Directory -Path $collisionFolder)
                    $collisionFile=Join-Path $collisionFolder 'preserve.txt'
                } else { $collisionFile=$collisionFolder+'.zip' }
                [IO.File]::WriteAllText($collisionFile,'existing archive - do not overwrite')
            }
            Step $daily 'Initialize daily archive'
            Step $daily 'Stage archive day'
            if($InsertAfterSnapshot -and !$Retry -and !$package.Variables['User::JobFailed'].Value -and $package.Variables['User::ArchiveJobId'].Value -eq 1 -and !$insertedDay) {
                $insertedDay=$package.Variables['User::CurrentDateFrom'].Value
                $dbInsert=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $dbInsert.Open()
                try {
                    $insert=$dbInsert.CreateCommand(); $insert.CommandText="SET IDENTITY_INSERT dbo.Orders ON; INSERT dbo.Orders(OrderNo,CreatedAt,Note,Amount) VALUES(4000,@Day,N'Inserted after snapshot',1); SET IDENTITY_INSERT dbo.Orders OFF;"
                    [void]$insert.Parameters.AddWithValue('@Day',$insertedDay); [void]$insert.ExecuteNonQuery()
                } finally { $dbInsert.Dispose() }
            }
            while(!$package.Variables['User::JobFailed'].Value -and $package.Variables['User::BatchHasRows'].Value) {
                foreach($name in @('Prepare batch select query','Read archive batch','Write batch to CSV')) { Step $batches $name }
            }
            foreach($name in @('Verify exported day','Create daily ZIP','Verify ZIP integrity','Delete archived day','Verify deleted row count','Drop staged day','Delete temporary CSV files')) { Step $daily $name }
            $package.Variables['User::CurrentDateFrom'].Value=([datetime]$package.Variables['User::CurrentDateFrom'].Value).AddDays(1)
        }
        foreach($name in @('Save job result','Log job result')) { Step $tables $name }
    }
    $result='Individual native tasks completed (scheduler not exercised)'
}
$messages=@($package.Errors | ForEach-Object Description)
$messages | Set-Content -LiteralPath (Join-Path $config.RunDirectory 'native-errors.txt')
Write-Output "Package result: $result"
$messages | Write-Output
$db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
$jobParts=$JobsTable.Split('.')
$jobIdentifier='['+$jobParts[0].Trim('[',']').Replace(']',']]')+'].['+$jobParts[1].Trim('[',']').Replace(']',']]')+']'
$db.Open()
try {
    $cmd=$db.CreateCommand()
    $cmd.CommandText='SELECT Id,LastProcessedStatus,ErrorMessage FROM '+$jobIdentifier+' ORDER BY Id;'
    $table=New-Object Data.DataTable
    $table.Load($cmd.ExecuteReader())
    $table | Format-Table -AutoSize | Out-String | Write-Output
    $successful=if($FailureMode -eq 'None') {@(1,3,4)} else {@(3,4)}
    foreach($id in $successful) {
        $job=@($table.Rows | Where-Object Id -eq $id)[0]
        if($job.LastProcessedStatus -ne 'Success') { throw "Job $id did not succeed" }
    }
    if(@($table.Rows | Where-Object Id -eq 2)[0].LastProcessedStatus -ne 'Error') { throw 'Expected missing date column failure' }
    if($FailureMode -ne 'None' -and @($table.Rows | Where-Object Id -eq 1)[0].LastProcessedStatus -ne 'Error') { throw 'Expected injected failure' }
    $cmd.CommandText='SELECT (SELECT COUNT(*) FROM dbo.Orders)+(SELECT COUNT(*) FROM audit.Events);'
    $sourceExpected=if($InsertAfterSnapshot) {4} elseif($FailureMode -eq 'None') {3} else {2509}
    if($cmd.ExecuteScalar() -ne $sourceExpected) { throw 'Unexpected source rows after deletion' }
    if($InsertAfterSnapshot) { $cmd.CommandText='SELECT COUNT(*) FROM dbo.Orders WHERE OrderNo=4000;'; if($cmd.ExecuteScalar() -ne 1) { throw 'Unstaged row was deleted' } }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zips=@(Get-ChildItem -LiteralPath $output -Filter '*.zip' -Recurse)
    $rowCount=0; $orderKeys=@(); $csvCount=0
    foreach($zip in $zips) {
        if($FailureMode -eq 'ZipCollision' -and $zip.FullName -eq $collisionFile) { continue }
        $archive=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
        try {
            foreach($entry in $archive.Entries) {
                if($zip.BaseName -notmatch '^\d{4}_\d{2}_\d{2}$' -or $entry.Name -notmatch ('^'+[regex]::Escape($zip.BaseName)+'_part[1-9][0-9]*\.csv$')) { throw 'Unexpected ZIP/CSV naming' }
                if($entry.Name -notlike '*.csv' -or $entry.FullName -ne $entry.Name) { throw 'ZIP must contain flat CSV entries only' }
                $reader=New-Object IO.StreamReader($entry.Open())
                try { $content=$reader.ReadToEnd() } finally { $reader.Dispose() }
                $rows=@($content | ConvertFrom-Csv -Delimiter ';')
                if($rows.Count -lt 1 -or $rows.Count -gt $MaxRecordsPerCsv) { throw 'CSV limit/empty file violation' }
                $header=($content -split "`r?`n")[0]
                if($header -notmatch '^"[^"\r\n]+ \([^"\r\n]+\)"' -or $content.IndexOf($header,$header.Length) -ge 0) { throw 'Missing/repeated CSV header' }
                if($content -notmatch '^"') { throw 'Missing CSV header' }
                $rowCount+=$rows.Count; $csvCount++
                foreach($row in $rows) {
                    # Validate against the actual date header below, independent of fixture naming.
                    $dateProperty=$row.PSObject.Properties | Where-Object Name -match '(CreatedAt|HappenedAt).*datetime' | Select-Object -First 1
                    if($dateProperty -and ([datetime]$dateProperty.Value).ToString('yyyy_MM_dd') -ne $zip.Name.Substring(0,10)) { throw 'Mixed day CSV/ZIP' }
                    if($zip.Directory.Parent.Name -eq 'dbo.Orders') { $orderKeys+= [long]$row.'OrderNo (bigint)' }
                }
            }
        } finally { $archive.Dispose() }
    }
    $loose=@(Get-ChildItem -LiteralPath $output -Filter '*.csv' -Recurse)
    foreach($file in $loose) { $rowCount+=@(Import-Csv -LiteralPath $file.FullName -Delimiter ';').Count }
    $expected=if($Retry) {0} elseif($FailureMode -in @('Read','Stage','NullKey')) {1002} elseif($FailureMode -eq 'Write') {1003} elseif($FailureMode -eq 'Delete') {6012} elseif($FailureMode -eq 'ZipTest') {6012} elseif($FailureMode -eq 'Zip') {3507} elseif($FailureMode -in @('FolderCollision','ZipCollision')) {1002} else {3508}
    if($rowCount -ne $expected) { throw "Unexpected archived/retained CSV rows: $rowCount, expected $expected" }
    if($FailureMode -eq 'None') {
        if($loose.Count -ne 0) { throw 'Successful archive left loose CSV files' }
        if(!$Retry) {
            $expectedKeys=@(1..2505)+@(3000)
            if(@(Compare-Object $expectedKeys @($orderKeys | Sort-Object)).Count -gt 0 -or $orderKeys.Count -ne 2506) { throw 'CSV keys differ from eligible source keys' }
            if(!$SpreadDates -and $MaxRecordsPerCsv -eq 1000 -and $csvCount -lt 5) { throw 'Missing CSV splits' }
        } elseif($zips.Count -ne 0) { throw 'Retry created empty archives' }
    }
    if($FailureMode -in @('Zip','ZipTest') -and $loose.Count -lt 3) { throw 'ZIP failure did not retain source CSV files' }
    if($FailureMode -in @('FolderCollision','ZipCollision')) {
        if([IO.File]::ReadAllText($collisionFile) -ne 'existing archive - do not overwrite') { throw 'Existing destination changed' }
        if(@($table.Rows | Where-Object Id -eq 1)[0].ErrorMessage -notlike '*destination already exists*') { throw 'Missing collision diagnostic' }
    }
    $cmd.CommandText="SELECT COUNT(*) FROM $jobIdentifier WHERE LastProcessedStatus=N'Error' AND LastSuccesProcessedAt='2025-01-01';"
    $failedExpected=if($FailureMode -eq 'None') {1} else {2}
    if($cmd.ExecuteScalar() -ne $failedExpected) { throw 'Previous success date was overwritten on failure' }
    "PASS: native SQL tasks and ZIP arguments (process task requires SSDT); mode=$FailureMode; CSV rows=$rowCount; source rows=$sourceExpected; SQL error persisted; following jobs succeeded; previous success date preserved. Scheduler/event-handler execution requires SSDT." | Tee-Object -FilePath (Join-Path $config.RunDirectory $(if($Retry) {'native-retry-result.txt'} else {'native-result.txt'}))
} finally { $db.Dispose() }
