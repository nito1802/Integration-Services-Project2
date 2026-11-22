param([switch]$Interrupt,[switch]$Success,[switch]$Scenarios)
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
    if(!$Success) {
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
        $script.SetAttribute('ReadOnlyVariables',$script.GetAttribute('ReadOnlyVariables')+',User::TableName')
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
$connectionString='Data Source=.\SSISARCHIVE22;Integrated Security=True;TrustServerCertificate=True'
$connection=New-Object Data.SqlClient.SqlConnection($connectionString)
try {
    $connection.Open()
    $command=$connection.CreateCommand(); $command.CommandTimeout=900
    $seed=(Get-Content (Join-Path $root 'docker/ssis-test/Seed.sql') -Raw -Encoding UTF8).Replace('SsisArchiveTest',$database)
    foreach($batch in [regex]::Split($seed,'(?im)^\s*GO\s*$')) {
        if($batch.Trim()) { $command.CommandText=$batch; [void]$command.ExecuteNonQuery() }
    }
    if($Scenarios) {
        $connection.ChangeDatabase($database)
        $command.CommandText=Get-Content (Join-Path $root 'CreateArchiveJobRelations.sql') -Raw
        [void]$command.ExecuteNonQuery()
        $otherDatabase=$database+'_Other'
        $command.CommandText="CREATE DATABASE [$otherDatabase]; DELETE FROM Archive.ArchiveJobs;"
        [void]$command.ExecuteNonQuery()
        $command.CommandText=(Get-Content (Join-Path $root 'Integration Services Project2.Console/SeedAll.sql') -Raw).
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
DECLARE @sync bit=1;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=50,@parameter_name=N'SYNCHRONIZED',@parameter_value=@sync;
EXEC catalog.start_execution @execution_id=@execution;
SELECT @execution;
'@
    foreach($item in @(
        @('@connection',($connectionString+';Initial Catalog='+$database)),
        @('@jobs',($database+'.Archive.ArchiveJobs')),
        @('@relations',($database+'.Archive.ArchiveJobRelations')),
        @('@root',$archiveRoot))) {
        [void]$command.Parameters.Add($item[0],[Data.SqlDbType]::NVarChar,4000)
        $command.Parameters[$item[0]].Value=$item[1]
    }
    $execution=$command.ExecuteScalar()
    $command.Parameters.Clear()
    $command.CommandText="SELECT COUNT(*) FROM catalog.operation_messages WHERE operation_id=$execution AND (message LIKE N'%deadlock%' OR message LIKE N'%locks timed out%');"
    if($command.ExecuteScalar() -ne 0) { throw 'Variable deadlock occurred in full SSISDB execution' }
    $command.CommandText="SELECT status FROM catalog.executions WHERE execution_id=$execution;"
    if($command.ExecuteScalar() -ne $(if($Success){7}else{4})) { throw 'Unexpected package execution status' }
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
    if(!$Success -and ($data.Rows[0].LastProcessedStatus -ne 'Error' -or $data.Rows[0].ErrorMessage -notlike '*7-Zip stderr:*')) {
        throw 'Process error and diagnostics were not persisted'
    }
    if($Interrupt -and $data.Rows[0].ErrorMessage -notlike '*-1073741510*') {
        throw 'Expected the same interrupted process exit code as the reported failure'
    }
    if($data.Rows[1].LastProcessedStatus -ne 'Success' -or $data.Rows[2].LastProcessedStatus -ne 'Success') {
        throw 'Following archive jobs did not complete'
    }
    $command.CommandText='SELECT COUNT(*) FROM Demo.Orders;'
    if($command.ExecuteScalar() -ne $(if($Success){2}else{7502})) { throw 'Unexpected source rows after ZIP processing' }
    "PASS: full SSISDB execution $execution completed with Success=$Success, Interrupt=$Interrupt; no variable deadlocks; source counts and following jobs verified."
    $data | Format-List | Out-String -Width 220 | Write-Output
} finally { $connection.Dispose() }
