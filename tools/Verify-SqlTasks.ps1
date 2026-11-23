param([switch]$MultiDatabase,[switch]$Related,[ValidateSet('None','ChildWrite','ChildZip','Delete','Cycle')][string]$RelatedFailure='None',[string]$JobsTable='Archive.ArchiveJobs',[string]$RelationsTable='Archive.ArchiveJobRelations',[switch]$InsertAfterSnapshot,[switch]$Ssis2025,[switch]$KeyTypes,[switch]$NativeProcessTasks,[switch]$Retry,[switch]$FullPackage,[switch]$SpreadDates,[switch]$SparseDates,[ValidateSet('None','NullKey','Stage','Read','Write','Delete','Zip','ZipTest','FolderCollision','ZipCollision')][string]$FailureMode='None',[int]$MaxRecordsPerCsv=1000)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Script-Source.ps1')
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB test' }
if($Ssis2025) { [void][Reflection.Assembly]::LoadFrom('C:/Program Files/Microsoft Visual Studio/18/Insiders/Common7/IDE/PublicAssemblies/SSIS/170/Microsoft.SqlServer.ManagedDTS.dll') } else { [void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS') }
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$packagePath=if($Ssis2025) { Join-Path $root 'Integration Services Project2/Package.dtsx' } else { Join-Path $PSScriptRoot 'compatibility-test.dtsx' }
$package=$app.LoadPackage($packagePath,$null)
$package.Parameters['ConnectionString'].Value=$config.ConnectionString
$package.Parameters['ArchiveJobsTable'].Value=$JobsTable
$package.Parameters['ArchiveJobRelationsTable'].Value=$RelationsTable
$output=Join-Path $config.RunDirectory $(if($Retry -and !$Related) {'retry-csv'} else {'native-csv'})
[void](New-Item -ItemType Directory -Path $output -Force)
$package.Parameters['ArchiveRoot'].Value=$output
$package.Parameters['MaxRecordsPerCsv'].Value=$MaxRecordsPerCsv
foreach($connection in $package.Connections) { $connection.ConnectionString=$config.ConnectionString }

if($SpreadDates -and !$Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try { $cmd=$db.CreateCommand(); $cmd.CommandText='UPDATE dbo.Orders SET CreatedAt=DATEADD(day,-3-CONVERT(int,OrderNo%20),CONVERT(date,GETDATE())) WHERE OrderNo<=2505;'; [void]$cmd.ExecuteNonQuery() } finally { $db.Dispose() }
}
if($SparseDates -and !$Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $cmd.CommandText="UPDATE dbo.Orders SET CreatedAt=CASE WHEN OrderNo<=2505 THEN CONVERT(datetime2,'20200203') ELSE CONVERT(datetime2,'20250115') END WHERE OrderNo<=3000; UPDATE Archive.ArchiveJobs SET ArchiveOlderThanDays=50 WHERE Id=1;"
        [void]$cmd.ExecuteNonQuery()
    } finally { $db.Dispose() }
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
if($Related -and !$Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $cmd.CommandText=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
        [void]$cmd.ExecuteNonQuery()
        $cmd.CommandText=@"
DELETE FROM Archive.ArchiveJobs WHERE Id<>1;
CREATE TABLE dbo.OrderLines(Id int PRIMARY KEY,OrderId bigint NOT NULL REFERENCES dbo.Orders(OrderNo),Payload nvarchar(100));
CREATE INDEX IX_OrderLines_OrderId ON dbo.OrderLines(OrderId);
INSERT dbo.OrderLines SELECT CONVERT(int,OrderNo)*2,OrderNo,N'first' FROM dbo.Orders;
INSERT dbo.OrderLines SELECT CONVERT(int,OrderNo)*2+1,OrderNo,N'second' FROM dbo.Orders;
CREATE TABLE dbo.OrderNotes(Id int PRIMARY KEY,OrderId bigint NOT NULL REFERENCES dbo.Orders(OrderNo),Payload nvarchar(100));
INSERT dbo.OrderNotes VALUES(1,1,N'old note'),(2,3002,N'current note');
INSERT Archive.ArchiveJobRelations(DatabaseName,ChildTable,ParentKeyColumn,ChildKeyColumn,ParentTable)
VALUES(DB_NAME(),N'dbo.OrderLines',N'OrderNo',N'OrderId',N'dbo.Orders'),(DB_NAME(),N'dbo.OrderNotes',N'OrderNo',N'OrderId',N'dbo.Orders');
CREATE TABLE dbo.LineDetails(Id int PRIMARY KEY,OrderLineId int NOT NULL REFERENCES dbo.OrderLines(Id),Payload nvarchar(100));
INSERT dbo.LineDetails SELECT Id,Id,N'detail' FROM dbo.OrderLines;
INSERT Archive.ArchiveJobRelations(DatabaseName,ChildTable,ParentKeyColumn,ChildKeyColumn,ParentTable)
VALUES(DB_NAME(),N'dbo.LineDetails',N'Id',N'OrderLineId',N'dbo.OrderLines');
CREATE TABLE dbo.SharedDetails(Id int PRIMARY KEY,LineId int NOT NULL REFERENCES dbo.OrderLines(Id),NoteId int NOT NULL REFERENCES dbo.OrderNotes(Id));
INSERT dbo.SharedDetails VALUES(1,2,1),(2,6004,2);
INSERT Archive.ArchiveJobRelations(DatabaseName,ChildTable,ParentKeyColumn,ChildKeyColumn,ParentTable)
VALUES(DB_NAME(),N'dbo.SharedDetails',N'Id',N'LineId',N'dbo.OrderLines'),
      (DB_NAME(),N'dbo.SharedDetails',N'Id',N'NoteId',N'dbo.OrderNotes');
-- Unrelated cycles and an incoming edge from an unreachable parent must stay outside this root's graph.
INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
VALUES(DB_NAME(),N'dbo.UnrelatedA',N'dbo.UnrelatedB',N'Id',N'ParentId'),
      (DB_NAME(),N'dbo.UnrelatedB',N'dbo.UnrelatedA',N'Id',N'ParentId'),
      (DB_NAME(),N'dbo.UnreachableParent',N'dbo.SharedDetails',N'Id',N'LineId');
"@
        [void]$cmd.ExecuteNonQuery()
        if($RelatedFailure -eq 'Cycle') {
            $cmd.CommandText="INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn) VALUES(DB_NAME(),N'dbo.LineDetails',N'dbo.OrderLines',N'Id',N'Id');"
            [void]$cmd.ExecuteNonQuery()
        }
        if($RelatedFailure -eq 'Delete') {
            $cmd.CommandText="CREATE TRIGGER dbo.RejectParentDelete ON dbo.Orders INSTEAD OF DELETE AS THROW 50002,'Injected parent delete failure.',1;"
            [void]$cmd.ExecuteNonQuery()
        }
    } finally { $db.Dispose() }
}
if($Related -and !$Retry -and $RelationsTable -eq 'Archive.Relations custom') {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $cmd.CommandText="EXEC sys.sp_rename N'Archive.ArchiveJobRelations',N'Relations custom',N'OBJECT';"
        [void]$cmd.ExecuteNonQuery()
    } finally { $db.Dispose() }
}
if($Related -and $Retry) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand(); $cmd.CommandText="DROP TRIGGER IF EXISTS dbo.RejectParentDelete;"
        [void]$cmd.ExecuteNonQuery()
    } finally { $db.Dispose() }
}
if($MultiDatabase) {
    $otherDatabase=$config.Database+'_Other'
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $dataPath=(Join-Path $config.RunDirectory 'other.mdf').Replace("'","''")
        $logPath=(Join-Path $config.RunDirectory 'other.ldf').Replace("'","''")
        $cmd.CommandText="CREATE DATABASE [$otherDatabase] ON PRIMARY (NAME=N'OtherData',FILENAME=N'$dataPath') LOG ON (NAME=N'OtherLog',FILENAME=N'$logPath');"
        [void]$cmd.ExecuteNonQuery()
        $cmd.CommandText=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
        [void]$cmd.ExecuteNonQuery()
        $cmd.CommandText='DELETE FROM Archive.ArchiveJobs;'
        [void]$cmd.ExecuteNonQuery()
        $seed=(Get-Content (Join-Path $root 'Integration Services Project2.Console/SeedAll.sql') -Raw).
            Replace('nito_superDb',$config.Database).Replace('nito_SomeApps',$otherDatabase)
        $transaction=$db.BeginTransaction()
        $cmd.Transaction=$transaction
        try {
            $cmd.CommandText=$seed
            [void]$cmd.Parameters.Add('@DatabaseName',[Data.SqlDbType]::NVarChar,128)
            foreach($database in @($config.Database,$otherDatabase)) {
                $cmd.Parameters['@DatabaseName'].Value=$database
                [void]$cmd.ExecuteNonQuery()
            }
            $transaction.Commit()
        } catch { $transaction.Rollback(); throw }
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
    $names=@('Prepare job queries','Initialize job variables','Prepare metadata and date queries','Initialize daily archive','Prepare batch select query','Write batch to CSV','Verify exported day','Verify deleted row count','Log job result','Capture SQL error','Prepare export schema and header','Delete temporary CSV files','Prepare related archive group','Prepare archive member','Prepare member export schema','Collect archive member deletion','Prepare group deletion','Finalize successful archives','Plan archive graph','Collect ZIP process diagnostics','Create daily ZIP','Verify ZIP integrity')
    for($i=0;$i -lt $names.Count;$i++) {
                $sourceName=if($names[$i] -in @('Create daily ZIP','Verify ZIP integrity')) {'Run ZIP process'} elseif($names[$i] -eq 'Prepare member export schema') {'Prepare export schema and header'} else {$names[$i]}
        $main=Get-Content -LiteralPath (Join-Path $root ('scripts/'+$sourceName+'.cs')) -Raw
        if($RelatedFailure -eq 'ChildWrite' -and $names[$i] -eq 'Write batch to CSV') {
            $main=$main.Replace('writer.WriteLine();','writer.WriteLine(); if (Convert.ToString(Dts.Variables["User::TableName"].Value) == "dbo.OrderLines") throw new IOException("Injected child CSV failure.");')
        }
        if($FailureMode -eq 'Write' -and $names[$i] -eq 'Write batch to CSV') {
            $main=$main.Replace('writer.WriteLine();','writer.WriteLine(); if (Convert.ToString(Dts.Variables["User::TableName"].Value) == "dbo.Orders") throw new IOException("Injected write failure.");')
        }
        if($names[$i] -notin @('Prepare job queries','Log job result','Capture SQL error')) { $main=Get-JobScriptSource $main }
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
        $index=[Array]::IndexOf($names,$name)
        if($index -ge 0) {
            $probe.Variables.Clear()
            foreach($variable in $package.Variables) { $v=New-Object ProbeVariable; $v.Value=$variable.Value; $probe.Variables.Add($variable.QualifiedName,$v) }
            foreach($parameter in $package.Parameters) { $key='$Package::'+$parameter.Name; if(!$probe.Variables.ContainsKey($key)) { $probe.Variables.Add($key,(New-Object ProbeVariable)) }; $probe.Variables[$key].Value=$parameter.Value }
            $v=New-Object ProbeVariable; $v.Value=$name
            $probe.Variables['System::TaskName']=$v
            if(($FailureMode -eq 'Zip' -and $name -eq 'Create daily ZIP') -or
               ($FailureMode -eq 'ZipTest' -and $name -eq 'Verify ZIP integrity') -or
               ($RelatedFailure -eq 'ChildZip' -and $name -eq 'Verify ZIP integrity' -and
                $package.Variables['User::TableName'].Value -eq 'dbo.OrderLines')) {
                $variable=if($name -eq 'Create daily ZIP') {'ZipArguments'} else {'ZipTestArguments'}
                $probe.Variables['User::'+$variable].Value='invalid-command'
            }
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
            if($FailureMode -eq 'NullKey' -and $name -in @('Prepare export schema and header','Prepare member export schema') -and $package.Variables['User::ArchiveJobId'].Value -eq 1) {
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
            if($name -in @('Calculate retention cutoff','Read archive batch','Read column definitions','Read SQL types and keys','Find first archive day','Find next archive day','Stage archive day','Drop staged day','Stage parent day','Load archive members','Read member column definitions','Read member SQL types and keys','Delete archived day','Create daily ZIP','Verify ZIP integrity')) {
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
    $members=$daily.Executables['For each archive member']
    $batches=$members.Executables['Process daily batches']
    foreach($job in $jobs.Rows) {
        foreach($entry in @(@('ArchiveJobId','Id'),@('DatabaseName','DatabaseName'),@('TableName','TableName'),@('Days','ArchiveOlderThanDays'),@('ColumnDate','DateColumn'))) {
            $package.Variables['User::'+$entry[0]].Value=$job[$entry[1]]
        }
        foreach($name in @('Mark job as started','Initialize job variables','Prepare metadata and date queries','Read column definitions','Read SQL types and keys','Prepare export schema and header','Calculate retention cutoff','Find first archive day')) { Step $tables $name }
        $visitedDays=0
        while(!$package.Variables['User::JobFailed'].Value -and $package.Variables['User::CurrentDateFrom'].Value -lt $package.Variables['User::CutoffDate'].Value) {
            $visitedDays++
            if($SparseDates -and $package.Variables['User::ArchiveJobId'].Value -eq 1 -and $visitedDays -gt 2) { throw 'Visited an empty day between 2020 and 2025' }
            if($package.Variables['User::ArchiveJobId'].Value -eq 1 -and $FailureMode -in @('FolderCollision','ZipCollision')) {
                $day=([datetime]$package.Variables['User::CurrentDateFrom'].Value).ToString('yyyy_MM_dd')
                $year=([datetime]$package.Variables['User::CurrentDateFrom'].Value).ToString('yyyy')
                $months=@('styczen','luty','marzec','kwiecien','maj','czerwiec','lipiec','sierpien','wrzesien','pazdziernik','listopad','grudzien')
                $month=$months[([datetime]$package.Variables['User::CurrentDateFrom'].Value).Month-1]
                $collisionFolder=Join-Path $output "$($config.Database)/dbo.Orders/$year/$month/$day"
                [void](New-Item -ItemType Directory -Path (Split-Path $collisionFolder -Parent) -Force)
                if($FailureMode -eq 'FolderCollision') {
                    [void](New-Item -ItemType Directory -Path $collisionFolder)
                    $collisionFile=Join-Path $collisionFolder 'stale.csv'
                } else { $collisionFile=$collisionFolder+'.zip' }
                [IO.File]::WriteAllText($collisionFile,'existing archive - do not overwrite')
            }
            foreach($name in @('Prepare related archive group','Stage parent day','Load archive members','Plan archive graph')) { Step $daily $name }
            if($package.Variables['User::JobFailed'].Value) { break }
            $memberRows=$package.Variables['User::ArchiveMembers'].Value.Tables[0].Copy()
            foreach($memberRow in $memberRows.Rows) {
                foreach($entry in @(@('MemberSchema','ChildSchema'),@('MemberTable','ChildTable'),@('MemberParentKey','ParentKeyColumn'),@('MemberChildKey','ChildKeyColumn'),@('MemberPlanSource','SourceSql'))) {
                    $package.Variables['User::'+$entry[0]].Value=$memberRow[$entry[1]]
                }
                foreach($name in @('Prepare archive member','Read member column definitions','Read member SQL types and keys','Prepare member export schema','Initialize daily archive','Drop previous member snapshot','Stage archive day')) { Step $members $name }
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
                foreach($name in @('Verify exported day','Create daily ZIP','Verify ZIP integrity','Collect ZIP process diagnostics','Collect archive member deletion')) { Step $members $name }
            }
            foreach($name in @('Prepare group deletion','Delete archived day','Finalize successful archives','Find next archive day')) { Step $daily $name }

        }
        if($SparseDates -and !$Retry -and $package.Variables['User::ArchiveJobId'].Value -eq 1 -and $visitedDays -ne 2) { throw 'Expected exactly two archive days' }
        if($SparseDates -and $package.Variables['User::ArchiveJobId'].Value -eq 1) { Write-Output ("Sparse data: visited days = $visitedDays" ) }
        foreach($name in @('Save job result','Log job result')) { Step $tables $name }
    }
    $result='Individual native tasks completed (scheduler not exercised)'
}
if($MultiDatabase) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $cmd.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobs WHERE LastProcessedStatus=N'Success';"
        if($cmd.ExecuteScalar() -ne 80) {
            $cmd.CommandText='SELECT TableName,DatabaseName,ErrorMessage FROM Archive.ArchiveJobs WHERE LastProcessedStatus<>N''Success'';'
            $t=New-Object Data.DataTable; $t.Load($cmd.ExecuteReader())
            throw ($t | Format-List | Out-String)
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        foreach($database in @($config.Database,$otherDatabase)) {
            $cmd.CommandText="SELECT SUM(p.rows) FROM [$database].sys.tables t JOIN [$database].sys.schemas s ON s.schema_id=t.schema_id JOIN [$database].sys.partitions p ON p.object_id=t.object_id AND p.index_id IN(0,1) WHERE s.name=N'ArchiveScenarioTest';"
            if($cmd.ExecuteScalar() -ne 65) { throw "Unexpected remaining data in $database" }
            $folder=Join-Path $output $database
            $rows=0
            $keys=New-Object 'System.Collections.Generic.HashSet[string]'
            foreach($zip in (Get-ChildItem $folder -Recurse -Filter '*.zip')) {
                $archive=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
                try {
                    foreach($entry in $archive.Entries) {
                        $reader=New-Object IO.StreamReader($entry.Open())
                        try { $csv=@($reader.ReadToEnd() | ConvertFrom-Csv -Delimiter ';') }
                        finally { $reader.Dispose() }
                        foreach($row in $csv) {
                            $key=$zip.Directory.Parent.Parent.Name+':'+$row.'Id (int)'
                            if(!$keys.Add($key)) { throw "Repeated archive key $key in $database" }
                        }
                        $rows+=$csv.Count
                    }
                } finally { $archive.Dispose() }
            }
            if($rows -ne 124) { throw "Unexpected exported count $rows in $database" }
            Write-Output "PASS: $database, 40 jobs, 25 relations, 124 unique exported rows, 65 retained rows."
        }
        if(@(Get-ChildItem $output -Recurse -Filter '*.csv').Count) { throw 'Loose CSV files remain' }
    } finally { $db.Dispose() }
    exit 0
}
if($Related) {
    $db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString); $db.Open()
    try {
        $cmd=$db.CreateCommand()
        $cmd.CommandText="SELECT LastProcessedStatus FROM Archive.ArchiveJobs WHERE Id=1;"
        $expectedStatus=if($RelatedFailure -eq 'None') {'Success'} else {'Error'}
        $actualStatus=$cmd.ExecuteScalar()
        if($actualStatus -ne $expectedStatus) {
            $cmd.CommandText="SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;"
            throw "Expected $expectedStatus, got $actualStatus. $($cmd.ExecuteScalar())"
        }
        foreach($entry in @(@('Orders',2,2508),@('OrderLines',4,5016),@('OrderNotes',1,2),@('LineDetails',4,5016),@('SharedDetails',1,2))) {
            $cmd.CommandText="SELECT COUNT(*) FROM dbo.$($entry[0]);"
            $expected=if($RelatedFailure -eq 'None') {$entry[1]} else {$entry[2]}
            if($cmd.ExecuteScalar() -ne $expected) { throw "Unexpected remaining count in $($entry[0]), expected $expected" }
        }
        if($RelatedFailure -eq 'Cycle') {
            if(@(Get-ChildItem $output -Recurse -File).Count) { throw 'Cycle was not rejected before export' }
            $cmd.CommandText="SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;"
            if($cmd.ExecuteScalar() -notlike '*cycle*') { throw 'Missing cycle diagnostic' }
        }
        if($RelatedFailure -eq 'Delete') {
            if(!(Get-ChildItem $output -Recurse -Filter '*.csv') -or !(Get-ChildItem $output -Recurse -Filter '*.zip')) {
                throw 'Failed delete did not preserve CSV and ZIP files'
            }
        }
        if($RelatedFailure -eq 'None') {
            if(@(Get-ChildItem $output -Recurse -File | Where-Object { $_.Extension -eq '.csv' -or $_.Name -like '*_retry_*' }).Count) {
                throw 'Successful group left temporary CSV or retry archives'
            }
            if(@(Get-ChildItem $output -Recurse -Directory | Where-Object { $_.Name -match '^\d{4}_\d{2}_\d{2}($|_retry_)' }).Count) {
                throw 'Successful group left temporary day directories'
            }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            foreach($entry in @(@('Orders',2506),@('OrderLines',5012),@('OrderNotes',1),@('LineDetails',5012),@('SharedDetails',1))) {
                $total=0
                $folder=Join-Path $output "$($config.Database)/dbo.$($entry[0])"
                $latestZips=Get-ChildItem $folder -Recurse -Filter '*.zip' |
                    Group-Object { $_.BaseName.Substring(0,10) } |
                    ForEach-Object { $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
                foreach($zip in $latestZips) {
                    $archive=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
                    try {
                        foreach($csv in $archive.Entries) {
                            $reader=New-Object IO.StreamReader($csv.Open())
                            try { $text=$reader.ReadToEnd(); $total+=@($text | ConvertFrom-Csv -Delimiter ';').Count }
                            finally { $reader.Dispose() }
                        }
                    } finally { $archive.Dispose() }
                }
                if($total -ne $entry[1]) { throw "Unexpected archived row count for $($entry[0]): $total" }
            }
        }
        Write-Output "PASS: related archive, mode=$RelatedFailure retry=$Retry. $output"
    } finally { $db.Dispose() }
    exit 0
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
    $successful=if($FailureMode -in @('None','FolderCollision','ZipCollision')) {@(1,3,4)} else {@(3,4)}
    foreach($id in $successful) {
        $job=@($table.Rows | Where-Object Id -eq $id)[0]
        if($job.LastProcessedStatus -ne 'Success') { throw "Job $id did not succeed" }
    }
    if(@($table.Rows | Where-Object Id -eq 2)[0].LastProcessedStatus -ne 'Error') { throw 'Expected missing date column failure' }
    if($FailureMode -notin @('None','FolderCollision','ZipCollision') -and @($table.Rows | Where-Object Id -eq 1)[0].LastProcessedStatus -ne 'Error') { throw 'Expected injected failure' }
    $cmd.CommandText='SELECT (SELECT COUNT(*) FROM dbo.Orders)+(SELECT COUNT(*) FROM audit.Events);'
    $sourceExpected=if($InsertAfterSnapshot) {4} elseif($FailureMode -in @('None','FolderCollision','ZipCollision')) {3} else {2509}
    if($cmd.ExecuteScalar() -ne $sourceExpected) { throw 'Unexpected source rows after deletion' }
    if($InsertAfterSnapshot) { $cmd.CommandText='SELECT COUNT(*) FROM dbo.Orders WHERE OrderNo=4000;'; if($cmd.ExecuteScalar() -ne 1) { throw 'Unstaged row was deleted' } }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zips=@(Get-ChildItem -LiteralPath $output -Filter '*.zip' -Recurse)
    $rowCount=0; $orderKeys=@(); $csvCount=0
    foreach($zip in $zips) {
        $archive=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
        try {
            foreach($entry in $archive.Entries) {
                if($zip.BaseName -notmatch '^\d{4}_\d{2}_\d{2}(_retry_[a-f0-9]{32})?$' -or $entry.Name -notmatch ('^'+[regex]::Escape($zip.BaseName.Substring(0,10))+'_part[1-9][0-9]*\.csv$')) { throw 'Unexpected ZIP/CSV naming' }
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
                    if($zip.Directory.Parent.Parent.Name -eq 'dbo.Orders') { $orderKeys+= [long]$row.'OrderNo (bigint)' }
                }
            }
        } finally { $archive.Dispose() }
    }
    $loose=@(Get-ChildItem -LiteralPath $output -Filter '*.csv' -Recurse)
    foreach($file in $loose) { $rowCount+=@(Import-Csv -LiteralPath $file.FullName -Delimiter ';').Count }
    $expected=if($Retry) {0} elseif($FailureMode -in @('Read','Stage','NullKey')) {1002} elseif($FailureMode -eq 'Write') {1003} elseif($FailureMode -eq 'Delete') {6012} elseif($FailureMode -eq 'ZipTest') {6012} elseif($FailureMode -eq 'Zip') {3507} elseif($FailureMode -in @('FolderCollision','ZipCollision')) {3508} else {3508}
    if($rowCount -ne $expected) { throw "Unexpected archived/retained CSV rows: $rowCount, expected $expected" }
    if($FailureMode -in @('None','FolderCollision','ZipCollision')) {
        if($loose.Count -ne 0) { throw 'Successful archive left loose CSV files' }
        if(!$Retry) {
            $expectedKeys=@(1..2505)+@(3000)
            if(@(Compare-Object $expectedKeys @($orderKeys | Sort-Object)).Count -gt 0 -or $orderKeys.Count -ne 2506) { throw 'CSV keys differ from eligible source keys' }
            if(!$SpreadDates -and $MaxRecordsPerCsv -eq 1000 -and $csvCount -lt 5) { throw 'Missing CSV splits' }
        } elseif($zips.Count -ne 0) { throw 'Retry created empty archives' }
    }
    if($FailureMode -in @('Zip','ZipTest') -and $loose.Count -lt 3) { throw 'ZIP failure did not retain source CSV files' }
    if($FailureMode -in @('FolderCollision','ZipCollision')) {
        if($FailureMode -eq 'FolderCollision' -and (Test-Path $collisionFile)) { throw 'Stale CSV was not cleaned up' }
        if(@(Get-ChildItem $output -Recurse -Filter '*_retry_*').Count) { throw 'Successful collision retry left temporary files' }

    }
    $cmd.CommandText="SELECT COUNT(*) FROM $jobIdentifier WHERE LastProcessedStatus=N'Error' AND LastSuccesProcessedAt='2025-01-01';"
    $failedExpected=if($FailureMode -in @('None','FolderCollision','ZipCollision')) {1} else {2}
    if($cmd.ExecuteScalar() -ne $failedExpected) { throw 'Previous success date was overwritten on failure' }
    "PASS: native SQL tasks and ZIP arguments (process task requires SSDT); mode=$FailureMode; CSV rows=$rowCount; source rows=$sourceExpected; SQL error persisted; following jobs succeeded; previous success date preserved. Scheduler/event-handler execution requires SSDT." | Tee-Object -FilePath (Join-Path $config.RunDirectory $(if($Retry) {'native-retry-result.txt'} else {'native-result.txt'}))
} finally { $db.Dispose() }
