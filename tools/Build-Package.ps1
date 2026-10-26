param([switch]$CompatibilityTest)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$project=Join-Path $root 'Integration Services Project2'
$packagePath=Join-Path $project 'Package.dtsx'
$backup=Join-Path $PSScriptRoot 'original.Package.dtsx'
if(!(Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $packagePath -Destination $backup }
$current=[xml](Get-Content -LiteralPath $packagePath -Raw)
$currentNs=New-Object Xml.XmlNamespaceManager($current.NameTable)
$currentNs.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$currentValues=@{}
$currentParameterIds=@{}
foreach($name in @('ConnectionString','ArchiveJobsTable','ArchiveRoot','MaxRecordsPerCsv')) {
    $valueNode=$current.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="'+$name+'"]/DTS:Property[@DTS:Name="ParameterValue"]',$currentNs)
    if($valueNode) { $currentValues[$name]=$valueNode.InnerText; $currentParameterIds[$name]=$valueNode.ParentNode.GetAttribute('DTSID','www.microsoft.com/SqlServer/Dts') }
}
$original=[xml](Get-Content -LiteralPath $backup -Raw)
$originalNs=New-Object Xml.XmlNamespaceManager($original.NameTable)
$originalNs.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$template=$original.SelectSingleNode('//ScriptProject',$originalNs)
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS')
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$package=$app.LoadPackage($backup,$null)
while($package.PrecedenceConstraints.Count -gt 0) { $package.PrecedenceConstraints.Remove(0) }
while($package.Executables.Count -gt 0) { $package.Executables.Remove(0) }
$package.VersionBuild=[Math]::Max($package.VersionBuild,[int]$current.DocumentElement.GetAttribute('VersionBuild','www.microsoft.com/SqlServer/Dts'))+1
$package.MaxConcurrentExecutables=1
$package.TransactionOption=[Microsoft.SqlServer.Dts.Runtime.DTSTransactionOption]::NotSupported
$package.DelayValidation=$true
$package.Description='Daily CSV parts with configurable row limit; verified daily ZIP before source deletion; daily ZIP via Execute Process Tasks.'
$package.Variables.Remove('User::SQLStatement')
function Add-Variable($name,$value) { [void]$package.Variables.Add($name,$false,'User',$value) }
foreach($name in @('Tables','BatchData','TableSchema','ShapeData','MetadataData')) { Add-Variable $name (New-Object object) }
foreach($name in @('JobsSelectSql','JobStartSql','JobResultSql','TableName','ColumnDate','ArchiwumPath','SQLStatement','FolderFullPath','OutputFile','KeyColumns','DatabaseName','JobError','CsvHeader','ShapeSql','MetadataSql','FirstDaySql','QualifiedTableName','StageDaySql','DeleteSql','ZipFile','ZipArguments','ZipTestArguments')) { Add-Variable $name '' }
foreach($name in @('DeletedRows','DayRows','DayExportedRows')) { Add-Variable $name ([long]0) }
foreach($name in @('Days','ArchiveJobId','FailedJobs')) { Add-Variable $name ([int]0) }
Add-Variable 'BatchNumber' ([long]0)
Add-Variable 'CurrentDateFrom' ([datetime]'2000-01-01')
Add-Variable 'CurrentDateTo' ([datetime]'2000-01-01')
Add-Variable 'DayHasFiles' $false
Add-Variable 'CutoffDate' ([datetime]'2000-01-01')
foreach($name in @('JobActive','JobFailed','BatchHasRows')) { Add-Variable $name $false }
$archiveRoot=[IO.Path]::GetDirectoryName([string]$package.Parameters['OutputFile'].Value)
foreach($obsolete in @('TableName','DateColumn','OlderThanDays','OutputFile','SevenZipPath')) { [void]$package.Parameters.Remove($obsolete) }
$p=$package.Parameters.Add('ArchiveRoot',[TypeCode]::String); $p.Value=$archiveRoot
if($currentValues.ContainsKey('ConnectionString')) { $package.Parameters['ConnectionString'].Value=$currentValues['ConnectionString'] }
if($currentValues.ContainsKey('ArchiveRoot')) { $package.Parameters['ArchiveRoot'].Value=$currentValues['ArchiveRoot'] }
foreach($entry in @(@('ArchiveJobsTable',[TypeCode]::String,'Archive.ArchiveJobs'),@('MaxRecordsPerCsv',[TypeCode]::Int32,1000))) {
    $p=$package.Parameters.Add($entry[0],$entry[1]); $p.Value=$entry[2]
    if($currentValues.ContainsKey($entry[0])) { $p.Value=[Convert]::ChangeType($currentValues[$entry[0]],$entry[1]) }
}
$connection=$package.Connections.Add('ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$connection.Name='ArchiveDb'
$connection.SetExpression('ConnectionString','@[$Package::ConnectionString]')
$connection.Properties['RetainSameConnection'].SetValue($connection,$true)
$connection.DelayValidation=$true
$statusConnection=$package.Connections.Add('ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$statusConnection.Name='ArchiveJobsDb'
$statusConnection.SetExpression('ConnectionString','@[$Package::ConnectionString]')
$statusConnection.Properties['RetainSameConnection'].SetValue($statusConnection,$true)
$statusConnection.DelayValidation=$true
function Link($container,$from,$to,$expression='') {
    $constraint=$container.PrecedenceConstraints.Add($from,$to)
    $constraint.Value=[Microsoft.SqlServer.Dts.Runtime.DTSExecResult]::Success
    if($expression) { $constraint.EvalOp=[Microsoft.SqlServer.Dts.Runtime.DTSPrecedenceEvalOp]::ExpressionAndConstraint; $constraint.Expression=$expression }
}
$scriptDefinitions=New-Object System.Collections.Generic.List[object]
function Add-Script($container,$name,$read,$write) {
    $hostTask=$container.Executables.Add('STOCK:ScriptTask'); $hostTask.Name=$name; $hostTask.DelayValidation=$true; $hostTask.FailPackageOnFailure=$true
    $sharedWrite=@('User::JobActive','User::JobFailed','User::JobError','User::FailedJobs','User::ArchiveJobId','User::OutputFile')
    $writes=@((@($write -split ',') + $sharedWrite) | Where-Object { $_ } | Select-Object -Unique)
    $reads=@((@($read -split ',') + @('User::TableName')) | Where-Object { $_ -and $_ -notin $writes } | Select-Object -Unique)
    $scriptDefinitions.Add(@{Name=$name; Read=($reads -join ','); Write=($writes -join ',')})
    return $hostTask
}
function Add-Sql($container,$name,$connectionName,$sql,$result='None',$variableSource=$false) {
    $hostTask=$container.Executables.Add('STOCK:SQLTask')
    $hostTask.Name=$name; $hostTask.DelayValidation=$true; $hostTask.FailPackageOnFailure=$true
    $task=$hostTask.InnerObject
    $task.Connection=$package.Connections[$connectionName].ID
    $task.SqlStatementSource=$sql
    if($variableSource) { $task.SqlStatementSourceType=[Enum]::Parse($task.SqlStatementSourceType.GetType(),'Variable') }
    $task.ResultSetType=[Enum]::Parse($task.ResultSetType.GetType(),'ResultSetType_'+$result)
    $task.TimeOut=300
    return $hostTask
}
function Bind-Input($hostTask,$parameter,$variable,[System.Data.DbType]$type,$size=-1) {
    $binding=$hostTask.InnerObject.ParameterBindings.Add()
    $binding.ParameterName=$parameter; $binding.DtsVariableName=$variable
    $binding.DataType=[int]$type; $binding.ParameterDirection=1; $binding.ParameterSize=$size
}
function Bind-Result($hostTask,$column,$variable) {
    $binding=$hostTask.InnerObject.ResultSetBindings.Add()
    $binding.ResultName=$column; $binding.DtsVariableName=$variable
}
function Job-Sql($hostTask,$handlerName,$skipAfterError=$true) {
    $hostTask.FailPackageOnFailure=$false; $hostTask.FailParentOnFailure=$false; $hostTask.MaximumErrorCount=0
    # OnError records the job failure. The scheduler can then reach Save job result.
    $hostTask.ForceExecutionResult=[Microsoft.SqlServer.Dts.Runtime.DTSForcedExecResult]::Success
    if($skipAfterError) { $hostTask.SetExpression('Disable','@[User::JobFailed]') }
    $handler=$hostTask.EventHandlers.Add('OnError'); $handler.MaximumErrorCount=0
    [void](Add-Script $handler $handlerName 'System::ErrorDescription' 'System::Propagate')
}
$prepareQueries=Add-Script $package 'Prepare job queries' '$Package::ArchiveJobsTable' 'User::JobsSelectSql,User::JobStartSql,User::JobResultSql'
$getSettings=Add-Sql $package 'Load archive jobs' 'ArchiveJobsDb' 'User::JobsSelectSql' 'Rowset' $true
Link $package $prepareQueries $getSettings
Bind-Result $getSettings '0' 'User::Tables'
$tables=$package.Executables.Add('STOCK:FOREACHLOOP'); $tables.Name='For each archive job'; $tables.DelayValidation=$true; $tables.FailPackageOnFailure=$true
$tables.ForEachEnumerator=$app.ForEachEnumeratorInfos['Foreach ADO Enumerator'].CreateNew()
$tables.ForEachEnumerator.InnerObject.DataObjectVariable='User::Tables'
foreach($entry in @(@('ArchiveJobId',0),@('DatabaseName',1),@('TableName',2),@('Days',3),@('ColumnDate',4))) { $mapping=$tables.VariableMappings.Add(); $mapping.VariableName='User::'+$entry[0]; $mapping.ValueIndex=$entry[1] }
Link $package $getSettings $tables
$startJob=Add-Sql $tables 'Mark job as started' 'ArchiveJobsDb' 'User::JobStartSql' 'None' $true
Bind-Input $startJob '@Id' 'User::ArchiveJobId' Int32
$prepareJob=Add-Script $tables 'Initialize job variables' '$Package::ArchiveRoot' 'User::ArchiwumPath,User::BatchHasRows,User::BatchNumber'
$begin=Add-Script $tables 'Prepare metadata and date queries' 'User::TableName,User::DatabaseName,User::ColumnDate,User::Days,$Package::MaxRecordsPerCsv' 'User::ShapeSql,User::MetadataSql,User::FirstDaySql,User::QualifiedTableName'
$cutoff=Add-Sql $tables 'Calculate retention cutoff' 'ArchiveDb' 'SELECT CONVERT(datetime2(7),DATEADD(day,-@Days,CONVERT(date,GETDATE()))) AS CutoffDate;' 'SingleRow'
Bind-Input $cutoff '@Days' 'User::Days' Int32
Bind-Result $cutoff '0' 'User::CutoffDate'
Job-Sql $cutoff 'Capture cutoff error'
Link $tables $startJob $prepareJob
Link $tables $prepareJob $begin
$shape=Add-Sql $tables 'Read column definitions' 'ArchiveDb' 'User::ShapeSql' 'Rowset' $true
Bind-Result $shape '0' 'User::ShapeData'
Job-Sql $shape 'Capture shape error'
$metadata=Add-Sql $tables 'Read SQL types and keys' 'ArchiveDb' 'User::MetadataSql' 'Rowset' $true
Bind-Result $metadata '0' 'User::MetadataData'
Job-Sql $metadata 'Capture metadata error'
$processMetadata=Add-Script $tables 'Prepare export schema and header' 'User::ShapeData,User::MetadataData' 'User::KeyColumns,User::TableSchema,User::CsvHeader'
Link $tables $begin $shape
Link $tables $shape $metadata
Link $tables $metadata $processMetadata
Link $tables $processMetadata $cutoff
$firstDay=Add-Sql $tables 'Find first archive day' 'ArchiveDb' 'User::FirstDaySql' 'SingleRow' $true
Bind-Input $firstDay '@Cutoff' 'User::CutoffDate' DateTime2
Bind-Result $firstDay '0' 'User::CurrentDateFrom'
Job-Sql $firstDay 'Capture first day error'
Link $tables $cutoff $firstDay
$daysLoop=$tables.Executables.Add('STOCK:FORLOOP'); $daysLoop.Name='For each archive day'; $daysLoop.DelayValidation=$true
$daysLoop.EvalExpression='!@[User::JobFailed] && @[User::CurrentDateFrom] < @[User::CutoffDate]'
$daysLoop.AssignExpression='@[User::CurrentDateFrom] = DATEADD("day",1,@[User::CurrentDateFrom])'
Link $tables $firstDay $daysLoop
$guid=Add-Script $daysLoop 'Initialize daily archive' 'User::CurrentDateFrom,User::ArchiwumPath,User::DatabaseName,User::TableName,User::QualifiedTableName,User::ColumnDate,User::KeyColumns' 'User::FolderFullPath,User::OutputFile,User::CurrentDateTo,User::BatchHasRows,User::BatchNumber,User::DayHasFiles,User::ZipFile,User::ZipArguments,User::ZipTestArguments,User::DayRows,User::DayExportedRows,User::StageDaySql,User::DeleteSql'
$stageDay=Add-Sql $daysLoop 'Stage archive day' 'ArchiveDb' 'User::StageDaySql' 'SingleRow' $true
Bind-Result $stageDay '0' 'User::DayRows'
Job-Sql $stageDay 'Capture day staging error'
Link $daysLoop $guid $stageDay
$batches=$daysLoop.Executables.Add('STOCK:FORLOOP'); $batches.Name='Process daily batches'; $batches.DelayValidation=$true
$batches.EvalExpression='!@[User::JobFailed] && @[User::BatchHasRows]'
Link $daysLoop $stageDay $batches
$construct=Add-Script $batches 'Prepare batch select query' 'User::KeyColumns,User::DayExportedRows,$Package::MaxRecordsPerCsv' 'User::SQLStatement'
$fetch=Add-Sql $batches 'Read archive batch' 'ArchiveDb' 'User::SQLStatement' 'Rowset' $true
Bind-Result $fetch '0' 'User::BatchData'
Job-Sql $fetch 'Capture batch read error'
$export=Add-Script $batches 'Write batch to CSV' 'User::BatchData,User::TableSchema,User::OutputFile,User::CutoffDate,User::TableName,User::CsvHeader,User::FolderFullPath,User::CurrentDateFrom' 'User::BatchNumber,User::BatchHasRows,User::DayExportedRows,User::DayHasFiles'

Link $batches $construct $fetch
Link $batches $fetch $export
$batches.PrecedenceConstraints[$batches.PrecedenceConstraints.Count-1].Value=[Microsoft.SqlServer.Dts.Runtime.DTSExecResult]::Success
function Add-ZipProcess($name,$argumentsVariable) {
    $hostTask=$daysLoop.Executables.Add('STOCK:ExecuteProcessTask'); $hostTask.Name=$name; $hostTask.DelayValidation=$true
    $task=$hostTask.InnerObject
    $task.RequireFullFileName=$true
    $task.Executable='C:\Program Files\7-Zip\7z.exe'
    $task.FailTaskIfReturnCodeIsNotSuccessValue=$true; $task.SuccessValue=0
    $task.TimeOut=600; $task.TerminateProcessAfterTimeOut=$true
    $hostTask.SetExpression('Arguments','@[User::'+$argumentsVariable+']')
    Job-Sql $hostTask ('Capture '+$name+' error')
    $hostTask.SetExpression('Disable','@[User::JobFailed] || !@[User::DayHasFiles]')
    return $hostTask
}
$zip=Add-ZipProcess 'Create daily ZIP' 'ZipArguments'
$testZip=Add-ZipProcess 'Verify ZIP integrity' 'ZipTestArguments'
$cleanup=Add-Script $daysLoop 'Delete temporary CSV files' 'User::FolderFullPath,User::DayHasFiles' ''
$verifyDay=Add-Script $daysLoop 'Verify exported day' 'User::DayRows,User::DayExportedRows' ''
$delete=Add-Sql $daysLoop 'Delete archived day' 'ArchiveDb' 'User::DeleteSql' 'SingleRow' $true
Bind-Result $delete '0' 'User::DeletedRows'
Job-Sql $delete 'Capture day delete error'
$delete.SetExpression('Disable','@[User::JobFailed] || !@[User::DayHasFiles]')
$checkDelete=Add-Script $daysLoop 'Verify deleted row count' 'User::DayRows,User::DeletedRows,User::DayHasFiles' ''
$dropDay=Add-Sql $daysLoop 'Drop staged day' 'ArchiveDb' "IF OBJECT_ID('tempdb..#ArchiveDay') IS NOT NULL DROP TABLE #ArchiveDay;"
Job-Sql $dropDay 'Capture day cleanup error' $false
Link $daysLoop $batches $verifyDay
Link $daysLoop $verifyDay $zip
Link $daysLoop $zip $testZip
Link $daysLoop $testZip $delete
Link $daysLoop $delete $checkDelete
Link $daysLoop $checkDelete $dropDay
Link $daysLoop $dropDay $cleanup
$setStatus=Add-Sql $tables 'Save job result' 'ArchiveJobsDb' 'User::JobResultSql' 'None' $true
Bind-Input $setStatus '@Id' 'User::ArchiveJobId' Int32
Bind-Input $setStatus '@Failed' 'User::JobFailed' Boolean
Bind-Input $setStatus '@Error' 'User::JobError' String
Link $tables $daysLoop $setStatus
$report=Add-Script $tables 'Log job result' '' ''
Link $tables $setStatus $report
$summary=Add-Script $package 'Check overall archive result' '' ''
Link $package $tables $summary
# Use the same SSIS error handling for C# and SQL tasks. Preparation resets the
# previous job's flags, so it must run even when the preceding job failed.
Job-Sql $prepareJob 'Capture preparation error' $false
foreach($task in @($begin,$processMetadata,$guid,$construct,$export,$verifyDay,$checkDelete,$cleanup)) {
    Job-Sql $task ('Capture '+$task.Name+' error')
}
$checkDelete.SetExpression('Disable','@[User::JobFailed] || !@[User::DayHasFiles]')
$skeleton=Join-Path $PSScriptRoot 'package-skeleton.dtsx'
$app.SaveToXml($skeleton,$package,$null)
$xml=[xml](Get-Content -LiteralPath $skeleton -Raw)
$ns=New-Object Xml.XmlNamespaceManager($xml.NameTable); $ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
# Keep parameter identities stable so SSDT does not lose cached debug references on rebuild.
foreach($parameterName in $currentParameterIds.Keys) {
    $parameterNode=$xml.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="'+$parameterName+'"]',$ns)
    if($parameterNode -and $currentParameterIds[$parameterName]) { [void]$parameterNode.SetAttribute('DTSID','www.microsoft.com/SqlServer/Dts',$currentParameterIds[$parameterName]) }
}
$common=Get-Content -LiteralPath (Join-Path $root 'scripts\Common.cs') -Raw
$compiler='C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\Roslyn\csc.exe'
$public='C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\PublicAssemblies\SSIS\170'
$buildDir=Join-Path $PSScriptRoot '.script-build'; [void](New-Item -ItemType Directory -Path $buildDir -Force)
foreach($definition in $scriptDefinitions) {
    $taskNode=$xml.SelectSingleNode('//DTS:Executable[@DTS:ObjectName="'+$definition.Name+'"]',$ns)
    $projectNode=$xml.ImportNode($template,$true)
    $oldName=$projectNode.GetAttribute('Name')
    $newName='ST_'+[Guid]::NewGuid().ToString('N')
    $projectNode.SetAttribute('Name',$newName)
    $projectNode.SetAttribute('ReadOnlyVariables',$definition.Read)
    $projectNode.SetAttribute('ReadWriteVariables',$definition.Write)
    $sourceName=if($definition.Name -like 'Capture * error') { 'Capture SQL error' } else { $definition.Name }
    $main=Get-Content -LiteralPath (Join-Path $root ('scripts\'+$sourceName+'.cs')) -Raw
    $source=$common.Replace('__NAMESPACE__',$newName).Replace('// __MAIN__',$main)
    foreach($item in $projectNode.SelectNodes('ProjectItem')) {
        $item.SetAttribute('Name',$item.GetAttribute('Name').Replace($oldName,$newName))
        $content=$item.InnerText.Replace($oldName,$newName)
        if($item.GetAttribute('Name') -eq 'ScriptMain.cs') { $content=$source }
        $content=$content -replace '(?m)[\t ]+$',''
        $item.InnerText=''; [void]$item.AppendChild($xml.CreateCDataSection($content))
    }
    $cs=Join-Path $buildDir ($newName+'.cs'); $dll=Join-Path $buildDir ($newName+'.dll')
    [IO.File]::WriteAllText($cs,$source,(New-Object Text.UTF8Encoding($false)))
    if($CompatibilityTest) {
        $projectNode.SetAttribute('VSTAMajorVersion','14')
        $managed=[Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS').Location
        $scriptTask=[Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ScriptTask').Location
    } else { $managed=Join-Path $public 'Microsoft.SqlServer.ManagedDTS.dll'; $scriptTask=Join-Path $public 'Microsoft.SqlServer.ScriptTask.dll' }
    & $compiler /nologo /target:library /optimize+ /debug- "/out:$dll" "/reference:$managed" "/reference:$scriptTask" /reference:System.Data.dll $cs
    if($LASTEXITCODE -ne 0) { throw ('Compilation failed: '+$definition.Name) }
    $binary=$projectNode.SelectSingleNode('BinaryItem'); $binary.SetAttribute('Name',$newName+'.dll'); $binary.InnerText=[Convert]::ToBase64String([IO.File]::ReadAllBytes($dll))
    $objectData=$taskNode.SelectSingleNode('DTS:ObjectData',$ns); $objectData.RemoveAll(); [void]$objectData.AppendChild($projectNode)
}
# Existing package identity, package parameters, and target version are preserved.
# The backup's layout refers to removed tasks; let SSDT arrange the current graph.
foreach($layout in @($xml.SelectNodes('//DTS:DesignTimeProperties',$ns))) { [void]$layout.ParentNode.RemoveChild($layout) }
$xml.DocumentElement.SetAttribute('LastModifiedProductVersion','www.microsoft.com/SqlServer/Dts','17.0.1016.0')
if($CompatibilityTest) { $destination=Join-Path $PSScriptRoot 'compatibility-test.dtsx' } else { $destination=$packagePath }
$xml.Save($destination)
& (Join-Path $PSScriptRoot 'Set-PackageLayout.ps1') -Path $destination
if (!$CompatibilityTest) {
    $projectFile=Join-Path $project 'Integration Services Project2.dtproj'
    $projectXml=[xml](Get-Content -LiteralPath $projectFile -Raw)
    $projectNs=New-Object Xml.XmlNamespaceManager($projectXml.NameTable)
    $projectNs.AddNamespace('SSIS','www.microsoft.com/SqlServer/SSIS')
    foreach($parameterNode in @($projectXml.SelectNodes('//SSIS:PackageMetaData/SSIS:Parameters/SSIS:Parameter',$projectNs))) {
        if($parameterNode.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS') -notin @('ConnectionString','ArchiveJobsTable','ArchiveRoot','MaxRecordsPerCsv')) {
            [void]$parameterNode.ParentNode.RemoveChild($parameterNode)
        }
    }
    $parameterList=$projectXml.SelectSingleNode('//SSIS:PackageMetaData/SSIS:Parameters',$projectNs)
    foreach($parameterName in @('ConnectionString','ArchiveJobsTable','ArchiveRoot','MaxRecordsPerCsv')) {
        $node=$parameterList.SelectSingleNode('SSIS:Parameter[@SSIS:Name="'+$parameterName+'"]',$projectNs)
        if(!$node) {
            $node=$parameterList.SelectSingleNode('SSIS:Parameter[@SSIS:Name="ConnectionString"]',$projectNs).CloneNode($true)
            $node.SetAttribute('Name','www.microsoft.com/SqlServer/SSIS',$parameterName)
            [void]$parameterList.AppendChild($node)
        }
        $node.SelectSingleNode('SSIS:Properties/SSIS:Property[@SSIS:Name="ID"]',$projectNs).InnerText=$xml.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="'+$parameterName+'"]',$ns).GetAttribute('DTSID','www.microsoft.com/SqlServer/Dts')
        $node.SelectSingleNode('SSIS:Properties/SSIS:Property[@SSIS:Name="Value"]',$projectNs).InnerText=[string]$package.Parameters[$parameterName].Value
        $node.SelectSingleNode('SSIS:Properties/SSIS:Property[@SSIS:Name="DataType"]',$projectNs).InnerText=if($parameterName -eq 'MaxRecordsPerCsv') {'9'} else {'18'}
    }
    # Synchronize debugger/deployment metadata with the package actually written to disk.
    $packageMetadata=$projectXml.SelectSingleNode('//SSIS:PackageMetaData/SSIS:Properties',$projectNs)
    foreach($entry in @(@('ID','DTSID'),@('Name','ObjectName'),@('VersionGUID','VersionGUID'),@('VersionBuild','VersionBuild'),@('VersionMajor','VersionMajor'),@('VersionMinor','VersionMinor'))) {
        $property=$packageMetadata.SelectSingleNode('SSIS:Property[@SSIS:Name="'+$entry[0]+'"]',$projectNs)
        $value=$xml.DocumentElement.GetAttribute($entry[1],'www.microsoft.com/SqlServer/Dts')
        if($property -and $value -ne '') { $property.InnerText=$value }
    }
    $projectXml.Save($projectFile)
}
Write-Output ('Built '+$destination)
