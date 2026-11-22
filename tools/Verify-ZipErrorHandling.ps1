param([switch]$Interrupt)
$ErrorActionPreference='Stop'
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
    $task.SelectSingleNode('DTS:PropertyExpression[@DTS:Name="Arguments"]',$ns).InnerText=
        '@[User::TableName] == "Demo.Orders" ? "invalid-command" : @[User::ZipTestArguments]'
    if($Interrupt) {
        $arguments=$task.SelectSingleNode('DTS:PropertyExpression[@DTS:Name="Arguments"]',$ns)
        $arguments.InnerText='@[User::TableName] == "Demo.Orders" ? "/c exit -1073741510" : @[User::ZipTestArguments]'
        $executable=$package.CreateElement('DTS','PropertyExpression',$ns.LookupNamespace('DTS'))
        [void]$executable.SetAttribute('Name',$ns.LookupNamespace('DTS'),'Executable')
        $cmd=($env:WINDIR+'\System32\cmd.exe').Replace('\','\\')
        $executable.InnerText='@[User::TableName] == "Demo.Orders" ? "'+$cmd+'" : "C:\\Program Files\\7-Zip\\7z.exe"'
        [void]$task.InsertBefore($executable,$arguments)
    }
    $entry.Delete()
    $writer=New-Object IO.StreamWriter($zip.CreateEntry('Package.dtsx').Open())
    try { $writer.Write($package.OuterXml) } finally { $writer.Dispose() }
    foreach($handler in $task.SelectNodes('.//ScriptProject')) {
        if($handler.ReadOnlyVariables -match 'User::ZipProcess(Output|Error)') {
            throw 'Process handler still requests producer output locks'
        }
    }
} finally { $zip.Dispose() }

[void](New-Item -ItemType Directory -Path $archiveRoot -Force)
& icacls.exe $archiveRoot /grant 'NT SERVICE\MSSQL$SSISARCHIVE22:(OI)(CI)M' | Out-Null
if($LASTEXITCODE -ne 0) { throw 'Cannot grant test archive access' }
$connectionString='Data Source=.\SSISARCHIVE22;Integrated Security=True;TrustServerCertificate=True'
$connection=New-Object Data.SqlClient.SqlConnection($connectionString)
try {
    $connection.Open()
    $command=$connection.CreateCommand(); $command.CommandTimeout=180
    $seed=(Get-Content (Join-Path $root 'docker/ssis-test/Seed.sql') -Raw -Encoding UTF8).Replace('SsisArchiveTest',$database)
    foreach($batch in [regex]::Split($seed,'(?im)^\s*GO\s*$')) {
        if($batch.Trim()) { $command.CommandText=$batch; [void]$command.ExecuteNonQuery() }
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
    if($command.ExecuteScalar() -ne 4) { throw 'Expected failed package result after injected ZIP error' }
    $connection.ChangeDatabase($database)
    $command.CommandText='SELECT Id,LastProcessedStatus,ErrorMessage FROM Archive.ArchiveJobs ORDER BY Id;'
    $data=New-Object Data.DataTable
    $data.Load($command.ExecuteReader())
    if($data.Rows[0].LastProcessedStatus -ne 'Error' -or $data.Rows[0].ErrorMessage -notlike '*7-Zip stderr:*') {
        throw 'Process error and diagnostics were not persisted'
    }
    if($Interrupt -and $data.Rows[0].ErrorMessage -notlike '*-1073741510*') {
        throw 'Expected the same interrupted process exit code as the reported failure'
    }
    if($data.Rows[1].LastProcessedStatus -ne 'Success' -or $data.Rows[2].LastProcessedStatus -ne 'Success') {
        throw 'Following archive jobs did not complete'
    }
    $command.CommandText='SELECT COUNT(*) FROM Demo.Orders;'
    if($command.ExecuteScalar() -ne 7502) { throw 'Source orders changed after ZIP failure' }
    "PASS: full SSISDB execution $execution captured ZIP failure without variable deadlocks; source rows retained; following jobs succeeded."
    $data | Format-List | Out-String -Width 220 | Write-Output
} finally { $connection.Dispose() }
