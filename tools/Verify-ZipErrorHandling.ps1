param([switch]$Interrupt,[switch]$Success,[switch]$Scenarios,[switch]$SqlFailure,[switch]$Related,[Alias('LogFolder')][string]$LogPath,[ValidateSet('Both','None','Details','Summary')][Alias('Logs')][string]$LogMode='Both')
$ErrorActionPreference='Stop'
if($Scenarios -and !$Success) { throw 'Scenarios require the successful execution mode' }
$root=Split-Path $PSScriptRoot -Parent
$run=Get-Date -Format 'yyyyMMdd_HHmmss'
$database='SsisZipFailure_'+$run
$archiveRoot='C:\ArchiveTest\ZipFailure_'+$run
$directory=Join-Path $root 'artifacts/sql2022'
$testIspac=Join-Path $directory ('zip-failure-'+$run+'.ispac')
Copy-Item (Join-Path $directory 'Archive.Sql2022.ispac') $testIspac
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$zip=[IO.Compression.ZipFile]::Open($testIspac,[IO.Compression.ZipArchiveMode]::Update)
try {
    $entry=$zip.GetEntry('Package.dtsx')
    $reader=New-Object IO.StreamReader($entry.Open())
    try { $package=[xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
    $ns=New-Object Xml.XmlNamespaceManager($package.NameTable)
    $ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
    $task=$package.SelectSingleNode('//DTS:Executable[@DTS:ObjectName="Verify ZIP integrity"]',$ns)
    if(!$Success -and !$SqlFailure) {
        $script=$task.SelectSingleNode('.//ScriptProject')
        $sourceItem=$script.SelectSingleNode('ProjectItem[@Name="ScriptMain.cs"]')
        $source=$sourceItem.InnerText
        $injection=if($Interrupt) {
            'if (Convert.ToString(Dts.Variables["User::TableName"].Value) == "Demo.Orders") { executable = @"'+$env:WINDIR+'\System32\cmd.exe"; arguments = "/c exit -1073741510"; }'
        } else {
            'if (Convert.ToString(Dts.Variables["User::TableName"].Value) == "Demo.Orders") arguments = "invalid-command";'
        }
        $source=$source.Replace('using (var process = new Process())',$injection+[Environment]::NewLine+'using (var process = new Process())')
        $sourceItem.InnerText=''; [void]$sourceItem.AppendChild($package.CreateCDataSection($source))
        if('User::TableName' -notin ($script.GetAttribute('ReadOnlyVariables') -split ',')) {
            $script.SetAttribute('ReadOnlyVariables',$script.GetAttribute('ReadOnlyVariables')+',User::TableName')
        }
        $sourcePath=Join-Path $directory ('zip-failure-'+$run+'.cs')
        $binaryDirectory=Join-Path $directory ('zip-failure-'+$run)
        [void](New-Item -ItemType Directory -Path $binaryDirectory -Force)
        $dllPath=Join-Path $binaryDirectory $script.SelectSingleNode('BinaryItem').GetAttribute('Name')
        [IO.File]::WriteAllText($sourcePath,$source)
        $public='C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\PublicAssemblies\SSIS\160'
        & 'C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:library "/out:$dllPath" "/reference:$public\Microsoft.SqlServer.ManagedDTS.dll" "/reference:$public\Microsoft.SqlServer.ScriptTask.dll" /reference:System.Data.dll $sourcePath
        if($LASTEXITCODE -ne 0) { throw 'Fault-injection compilation failed' }
        $script.SelectSingleNode('BinaryItem').InnerText=[Convert]::ToBase64String([IO.File]::ReadAllBytes($dllPath))
    }
    $entry.Delete()
    $writer=New-Object IO.StreamWriter($zip.CreateEntry('Package.dtsx').Open())
    try { $writer.Write($package.OuterXml) } finally { $writer.Dispose() }
    if(!$task.SelectSingleNode('DTS:ObjectData/ScriptProject',$ns)) { throw 'ZIP verification must use the console-free runner' }
} finally { $zip.Dispose() }

[void](New-Item -ItemType Directory -Path $archiveRoot -Force)
& icacls.exe $archiveRoot /grant 'NT SERVICE\MSSQL$SSISARCHIVE22:(OI)(CI)M' | Out-Null
if($LASTEXITCODE -ne 0) { throw 'Cannot grant test archive access' }
if(!$LogPath){$LogPath=Join-Path $archiveRoot 'logs'}
$detailsEnabled=$LogMode -in @('Both','Details')
$summaryEnabled=$LogMode -in @('Both','Summary')
if($LogMode -ne 'None') {
 [void](New-Item -ItemType Directory -Path $LogPath -Force)
 & icacls.exe $LogPath /grant 'NT SERVICE\MSSQL$SSISARCHIVE22:(OI)(CI)M' | Out-Null
 if($LASTEXITCODE -ne 0) { throw 'Cannot grant test log access' }
}
$pathExisted=Test-Path -LiteralPath $LogPath
$previousLogs=@(if($pathExisted){Get-ChildItem $LogPath -Filter 'archive_*.txt' | ForEach-Object {$_.FullName}})
$connectionString='Data Source=.\SSISARCHIVE22;Integrated Security=True;TrustServerCertificate=True'
$connection=New-Object Data.SqlClient.SqlConnection($connectionString)
try {
    $connection.Open()
    $command=$connection.CreateCommand(); $command.CommandTimeout=900
    $seed=(Get-Content (Join-Path $root 'docker/ssis-test/Seed.sql') -Raw -Encoding UTF8).Replace('SsisArchiveTest',$database)
    foreach($batch in [regex]::Split($seed,'(?im)^\s*GO\s*$')) {
        if($batch.Trim()) { $command.CommandText=$batch; [void]$command.ExecuteNonQuery() }
    }
    if($SqlFailure) {
        $connection.ChangeDatabase($database)
        $command.CommandText="CREATE TRIGGER Demo.FailArchiveDelete ON Demo.Orders INSTEAD OF DELETE AS THROW 50001,'Injected SQL delete failure',1;"
        [void]$command.ExecuteNonQuery()
    }
    if($Related) {
        $connection.ChangeDatabase($database)
        $migration=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
        $command.CommandText=$migration.Substring(0,$migration.IndexOf('END CATCH;')+'END CATCH;'.Length)
        [void]$command.ExecuteNonQuery()
        $command.CommandText=@'
CREATE TABLE Demo.OrderLines(Id int PRIMARY KEY,OrderId int NOT NULL REFERENCES Demo.Orders(Id));
INSERT Demo.OrderLines VALUES(101,1),(102,1),(103,2501),(104,7501);
CREATE TABLE Demo.LineDetails(Id int PRIMARY KEY,OrderLineId int NOT NULL REFERENCES Demo.OrderLines(Id));
INSERT Demo.LineDetails VALUES(201,101),(202,102),(203,103),(204,104);
INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
VALUES(DB_NAME(),N'Demo.Orders',N'Demo.OrderLines',N'Id',N'OrderId'),
      (DB_NAME(),N'Demo.OrderLines',N'Demo.LineDetails',N'Id',N'OrderLineId');
'@
        [void]$command.ExecuteNonQuery()
    }
    if($Scenarios) {
        $connection.ChangeDatabase($database)
        $command.CommandText=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
        [void]$command.ExecuteNonQuery()
        $otherDatabase=$database+'_Other'
        $command.CommandText="CREATE DATABASE [$otherDatabase]; DELETE FROM Archive.ArchiveJobs;"
        [void]$command.ExecuteNonQuery()
        $command.CommandText=(Get-Content (Join-Path $root 'tools/ArchiveScenarioFixture.sql') -Raw).
            Replace('nito_superDb',$database).Replace('nito_SomeApps',$otherDatabase)
        [void]$command.Parameters.Add('@DatabaseName',[Data.SqlDbType]::NVarChar,128)
        $transaction=$connection.BeginTransaction()
        $command.Transaction=$transaction
        try {
            foreach($source in @($database,$otherDatabase)) {
                $command.Parameters['@DatabaseName'].Value=$source
                [void]$command.ExecuteNonQuery()
            }
            $transaction.Commit()
        } catch { $transaction.Rollback(); throw }
        $command.Transaction=$null
        $command.Parameters.Clear()
    }
    $connection.ChangeDatabase('SSISDB')
    $command.CommandText="IF NOT EXISTS(SELECT 1 FROM catalog.folders WHERE name=N'ArchiveFailureTests') EXEC catalog.create_folder @folder_name=N'ArchiveFailureTests';"
    [void]$command.ExecuteNonQuery()
    $command.CommandText="EXEC catalog.deploy_project @folder_name=N'ArchiveFailureTests',@project_name=N'Archive.Sql2022',@project_stream=@bytes;"
    [void]$command.Parameters.Add('@bytes',[Data.SqlDbType]::VarBinary,-1)
    $command.Parameters['@bytes'].Value=[IO.File]::ReadAllBytes($testIspac)
    [void]$command.ExecuteNonQuery()
    $command.Parameters.Clear()
    $command.CommandText=@'
DECLARE @execution bigint;
EXEC catalog.create_execution @folder_name=N'ArchiveFailureTests',@project_name=N'Archive.Sql2022',@package_name=N'Package.dtsx',@execution_id=@execution OUTPUT;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ConnectionString',@parameter_value=@connection;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveJobsTable',@parameter_value=@jobs;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveJobRelationsTable',@parameter_value=@relations;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveRoot',@parameter_value=@root;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'LogPath',@parameter_value=@logs;
IF @setFlags=1 BEGIN
 EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'DetailsLog',@parameter_value=@details;
 EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'Summarylog',@parameter_value=@summary;
END;
DECLARE @sync bit=1;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=50,@parameter_name=N'SYNCHRONIZED',@parameter_value=@sync;
EXEC catalog.start_execution @execution_id=@execution;
SELECT @execution;
'@
    foreach($item in @(
        @('@connection',($connectionString+';Initial Catalog='+$database)),
        @('@jobs',($database+'.Archive.ArchiveJobs')),
        @('@relations',($database+'.Archive.ArchiveJobRelations')),
        @('@root',$archiveRoot),
        @('@logs',$LogPath))) {
        [void]$command.Parameters.Add($item[0],[Data.SqlDbType]::NVarChar,4000)
        $command.Parameters[$item[0]].Value=$item[1]
    }
    foreach($flag in @(@('@setFlags',($LogMode -ne 'None')),@('@details',$detailsEnabled),@('@summary',$summaryEnabled))) {
        [void]$command.Parameters.Add($flag[0],[Data.SqlDbType]::Bit)
        $command.Parameters[$flag[0]].Value=[bool]$flag[1]
    }
    $execution=$command.ExecuteScalar()
    $command.Parameters.Clear()
    $command.CommandText="SELECT COUNT(*) FROM catalog.operation_messages WHERE operation_id=$execution AND (message LIKE N'%deadlock%' OR message LIKE N'%locks timed out%');"
    if($command.ExecuteScalar() -ne 0) { throw 'Variable deadlock occurred in full SSISDB execution' }
    $command.CommandText="SELECT status FROM catalog.executions WHERE execution_id=$execution;"
    if($command.ExecuteScalar() -ne $(if($Success){7}else{4})) { throw 'Unexpected package execution status' }
    $logs=@(if(Test-Path -LiteralPath $LogPath){Get-ChildItem $LogPath -Filter 'archive_*.txt' | Where-Object {$_.FullName -notin $previousLogs}})
    if($logs.Count -ne ([int]$detailsEnabled+[int]$summaryEnabled)){throw 'Unexpected number of log files for selected flags'}
    if($LogMode -eq 'None' -and !$pathExisted -and (Test-Path -LiteralPath $LogPath)){throw 'Disabled logging created a directory'}
    $details=@($logs | Where-Object {$_.Name -like '*_details.txt'})
    $summary=@($logs | Where-Object {$_.Name -like '*_summary.txt'})
    if($details.Count -ne [int]$detailsEnabled -or $summary.Count -ne [int]$summaryEnabled){throw 'Wrong log type created'}
    if($LogMode -eq 'Both' -and $details[0].Name.Replace('_details.txt','_summary.txt') -ne $summary[0].Name){throw 'Log pair does not share the run identity'}
    $content=''; $summaryContent=''
    if($detailsEnabled) {
    $content=Get-Content $details[0].FullName -Raw -Encoding UTF8
    foreach($marker in @('RUN START','JOB START','JOB END','SQL START','SQL END','Create daily ZIP','Verify ZIP integrity','rows=','elapsedMs=',$(if($Success){'RUN SUCCESS'}else{'RUN ERROR'}))) {
        if(!$content.Contains($marker)){throw ('Missing progress marker: '+$marker)}
    }
    if(!$Success -and !$content.Contains('-1073741510') -and $Interrupt){throw 'ZIP failure is missing from file log'}
    }
    if($summaryEnabled) {
    $summaryContent=Get-Content $summary[0].FullName -Raw -Encoding UTF8
    foreach($marker in @('RUN START','TABLE START','TABLE END','JOB START','JOB END','RUN END','duration=','phase=export+zip',('RUN END | Package | status='+$(if($Success){'Success'}else{'Error'})))) {
        if(!$summaryContent.Contains($marker)){throw ('Missing summary marker: '+$marker)}
    }
    $jobEnds=@([regex]::Matches($summaryContent,'(?m)^.*\| JOB END \|.*elapsedMs=([0-9.]+)'))
    if($jobEnds.Count -ne $(if($Scenarios){80}else{3})){throw 'Expected one summary per job, including the empty job'}
    $runEnd=[regex]::Match($summaryContent,'(?m)^.*\| RUN END \|.*elapsedMs=([0-9.]+)')
    $jobMs=0.0
    foreach($job in $jobEnds){$jobMs += [double]::Parse($job.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)}
    $runMs=[double]::Parse($runEnd.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
    if($runMs -le 0 -or $runMs+2 -lt $jobMs){throw 'Run timing does not cover job timings'}
    if(!$Success -and !$SqlFailure -and $summaryContent -notmatch 'TABLE END[^\r\n]*status=Error'){throw 'Failed table export is not marked as Error in summary'}
    if($Related -and (!$summaryContent.Contains('TABLE END | Demo.OrderLines') -or !$summaryContent.Contains('TABLE END | Demo.LineDetails'))) {
        throw 'Missing child table timings in summary'
    }
    }
    Write-Output ('Logging mode '+$LogMode+' verified: '+(($logs | ForEach-Object {$_.FullName}) -join '; '))
    $connection.ChangeDatabase($database)
    if($Scenarios) {
        $command.CommandText="SELECT COUNT(*) FROM Archive.ArchiveJobs WHERE LastProcessedStatus=N'Success';"
        if($command.ExecuteScalar() -ne 80) { throw 'Not all scenario jobs succeeded' }
        foreach($source in @($database,$otherDatabase)) {
            $command.CommandText="SELECT SUM(p.rows) FROM [$source].sys.tables t JOIN [$source].sys.schemas s ON s.schema_id=t.schema_id JOIN [$source].sys.partitions p ON p.object_id=t.object_id AND p.index_id IN(0,1) WHERE s.name=N'ArchiveScenarioTest';"
            if($command.ExecuteScalar() -ne 65) { throw "Unexpected remaining rows in $source" }
        }
        if(@(Get-ChildItem $archiveRoot -Recurse -Filter '*.zip').Count -ne 200) { throw 'Expected 200 ZIP archives' }
        "PASS: full SSISDB execution $execution, 80 successful jobs in two databases; 200 ZIP archives; console-free creation and verification."
        exit 0
    }
    $command.CommandText='SELECT Id,LastProcessedStatus,ErrorMessage FROM Archive.ArchiveJobs ORDER BY Id;'
    $data=New-Object Data.DataTable
    $data.Load($command.ExecuteReader())
    if(!$Success -and !$SqlFailure -and ($data.Rows[0].LastProcessedStatus -ne 'Error' -or $data.Rows[0].ErrorMessage -notlike '*7-Zip stderr:*')) {
        throw 'Process error and diagnostics were not persisted'
    }
    if($SqlFailure -and ($data.Rows[0].LastProcessedStatus -ne 'Error' -or $data.Rows[0].ErrorMessage -notlike '*Injected SQL delete failure*' -or ($detailsEnabled -and !$content.Contains('SQL ERROR')))) {
        throw 'SQL failure was not persisted in both job result and progress log'
    }
    if($Interrupt -and $data.Rows[0].ErrorMessage -notlike '*-1073741510*') {
        throw 'Expected the same interrupted process exit code as the reported failure'
    }
    if($data.Rows[1].LastProcessedStatus -ne 'Success' -or $data.Rows[2].LastProcessedStatus -ne 'Success') {
        throw 'Following archive jobs did not complete'
    }
    $command.CommandText='SELECT COUNT(*) FROM Demo.Orders;'
    if($command.ExecuteScalar() -ne $(if($Success){2}else{7502})) { throw 'Unexpected source rows after ZIP processing' }
    if($Related -and $Success) {
        $command.CommandText='SELECT (SELECT COUNT(*) FROM Demo.OrderLines)+(SELECT COUNT(*) FROM Demo.LineDetails);'
        if($command.ExecuteScalar() -ne 2){throw 'Related source rows were not deleted correctly'}
    }
    "PASS: full SSISDB execution $execution completed with Success=$Success, Interrupt=$Interrupt; no variable deadlocks; source counts and following jobs verified."
    $data | Format-List | Out-String -Width 220 | Write-Output
} finally { $connection.Dispose() }
