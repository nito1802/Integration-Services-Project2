param([switch]$CompatibilityTest)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$project=Join-Path $root 'Integration Services Project2'
$packagePath=Join-Path $project 'Package.dtsx'
$backup=Join-Path $PSScriptRoot 'original.Package.dtsx'
if(!(Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $packagePath -Destination $backup }
$original=[xml](Get-Content -LiteralPath $backup -Raw)
$originalNs=New-Object Xml.XmlNamespaceManager($original.NameTable)
$originalNs.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$template=$original.SelectSingleNode('//ScriptProject',$originalNs)
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS')
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$package=$app.LoadPackage($backup,$null)
while($package.PrecedenceConstraints.Count -gt 0) { $package.PrecedenceConstraints.Remove(0) }
while($package.Executables.Count -gt 0) { $package.Executables.Remove(0) }
$package.VersionBuild=$package.VersionBuild+1
$package.MaxConcurrentExecutables=1
$package.DelayValidation=$true
$package.Description='CSV archive: configuration -> tables -> full days -> stable batches of 1000. One CSV per table and execution, in execution-date folder. Source tables are read only.'
$package.Variables.Remove('User::SQLStatement')
function Add-Variable($name,$value) { [void]$package.Variables.Add($name,$false,'User',$value) }
foreach($name in @('Tables')) { Add-Variable $name (New-Object object) }
foreach($name in @('TableName','ColumnDate','ArchiwumPath','BeginScript','CountSQL','SQLStatement','FolderFullPath','OutputFile','AddNumber','QuotedTable','QuotedColumn','OrderBy','SettingsSQL','CsvHeader')) { Add-Variable $name '' }
foreach($name in @('Days','DaysCounter','LoopCounter')) { Add-Variable $name ([int]0) }
foreach($name in @('FileRecordCounter','BatchNumber','DayExportedRows','TableExportedRows','TableExpectedRows')) { Add-Variable $name ([long]0) }
foreach($name in @('DateFrom','DateTo','CurrentDateFrom','CurrentDateTo')) { Add-Variable $name ([datetime]'2000-01-01') }
$settings=@'
SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.CasherSettings',N'U') IS NOT NULL
    EXEC sys.sp_executesql N'SELECT Id,TableName,Days,ColumnDate,ArchiwumPath FROM dbo.CasherSettings WHERE DictionaryType=N''Archiwum'' ORDER BY Id;';
ELSE
BEGIN
    RAISERROR('CasherSettings is absent. Using existing package parameters for one table.',10,1);
    SELECT CAST(0 AS int) AS Id,@TableName AS TableName,@Days AS Days,@DateColumn AS ColumnDate,@ArchiveRoot AS ArchiwumPath;
END;
'@
foreach($entry in @(@('SettingsQuery',$settings),@('ArchiveRoot',[IO.Path]::GetDirectoryName([string]$package.Parameters['OutputFile'].Value)))) {
    $p=$package.Parameters.Add($entry[0],[TypeCode]::String); $p.Value=$entry[1]
}
$package.Variables['SettingsSQL'].EvaluateAsExpression=$true
$package.Variables['SettingsSQL'].Expression='@[$Package::SettingsQuery]'
$connection=$package.Connections.Add('ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$connection.Name='ArchiveDb'
$connection.SetExpression('ConnectionString','@[$Package::ConnectionString]')
$connection.Properties['RetainSameConnection'].SetValue($connection,$true)
$connection.DelayValidation=$true
function Link($container,$from,$to,$expression='') {
    $constraint=$container.PrecedenceConstraints.Add($from,$to)
    $constraint.Value=[Microsoft.SqlServer.Dts.Runtime.DTSExecResult]::Success
    if($expression) { $constraint.EvalOp=[Microsoft.SqlServer.Dts.Runtime.DTSPrecedenceEvalOp]::ExpressionAndConstraint; $constraint.Expression=$expression }
}
function Add-Sql($container,$name,$source,$resultType,$results,$parameters) {
    $hostTask=$container.Executables.Add('Microsoft.ExecuteSQLTask'); $hostTask.Name=$name; $hostTask.DelayValidation=$true; $hostTask.FailPackageOnFailure=$true
    $task=$hostTask.InnerObject; $task.Connection=$connection.ID; $task.TimeOut=300
    $task.SqlStatementSourceType=[Microsoft.SqlServer.Dts.Tasks.ExecuteSQLTask.SqlStatementSourceType]::Variable
    $task.SqlStatementSource='User::'+$source
    $task.ResultSetType=[Microsoft.SqlServer.Dts.Tasks.ExecuteSQLTask.ResultSetType]$resultType
    foreach($entry in $results) { $binding=$task.ResultSetBindings.Add(); $binding.ResultName=$entry[0]; $binding.DtsVariableName='User::'+$entry[1] }
    foreach($entry in $parameters) {
        $binding=$task.ParameterBindings.Add(); $binding.ParameterName=$entry[0]; $binding.DtsVariableName=$entry[1]
        $binding.ParameterDirection=[Microsoft.SqlServer.Dts.Tasks.ExecuteSQLTask.ParameterDirections]::Input
        $binding.DataType=[int]$entry[2]; $binding.ParameterSize=-1
    }
    return $hostTask
}
$scriptDefinitions=New-Object System.Collections.Generic.List[object]
function Add-Script($container,$name,$read,$write) {
    $hostTask=$container.Executables.Add('STOCK:ScriptTask'); $hostTask.Name=$name; $hostTask.DelayValidation=$true; $hostTask.FailPackageOnFailure=$true
    $scriptDefinitions.Add(@{Name=$name; Read=$read; Write=$write})
    return $hostTask
}
$getSettings=Add-Sql $package 'Get Casher Settings' 'SettingsSQL' 'ResultSetType_Rowset' (,@('0','Tables')) @(@('@TableName','$Package::TableName',[Data.DbType]::String),@('@Days','$Package::OlderThanDays',[Data.DbType]::Int32),@('@DateColumn','$Package::DateColumn',[Data.DbType]::String),@('@ArchiveRoot','$Package::ArchiveRoot',[Data.DbType]::String))
$tables=$package.Executables.Add('STOCK:FOREACHLOOP'); $tables.Name='Foreach Loop Container'; $tables.DelayValidation=$true; $tables.FailPackageOnFailure=$true
$tables.ForEachEnumerator=$app.ForEachEnumeratorInfos['Foreach ADO Enumerator'].CreateNew()
$tables.ForEachEnumerator.InnerObject.DataObjectVariable='User::Tables'
foreach($entry in @(@('TableName',1),@('Days',2),@('ColumnDate',3),@('ArchiwumPath',4))) { $mapping=$tables.VariableMappings.Add(); $mapping.VariableName='User::'+$entry[0]; $mapping.ValueIndex=$entry[1] }
Link $package $getSettings $tables
$begin=Add-Script $tables 'BeginScript' 'User::TableName,User::ColumnDate,User::Days' 'User::BeginScript,User::LoopCounter,User::QuotedTable,User::QuotedColumn,User::OrderBy'
$days=Add-Sql $tables 'Count days diff' 'BeginScript' 'ResultSetType_SingleRow' @(@('0','DaysCounter'),@('1','DateFrom'),@('2','DateTo')) (,@('@Days','User::Days',[Data.DbType]::Int32))
$dayLoop=$tables.Executables.Add('STOCK:FORLOOP'); $dayLoop.Name='For Loop Container'; $dayLoop.DelayValidation=$true; $dayLoop.FailPackageOnFailure=$true
$dayLoop.InitExpression='@[User::LoopCounter] = 0'; $dayLoop.EvalExpression='@[User::LoopCounter] < @[User::DaysCounter]'; $dayLoop.AssignExpression='@[User::LoopCounter] = @[User::LoopCounter] + 1'
Link $tables $begin $days
$guid=Add-Script $tables 'GetGuid' 'System::StartTime,User::ArchiwumPath,User::TableName,User::QuotedTable' 'User::FolderFullPath,User::AddNumber,User::OutputFile,User::CsvHeader,User::TableExportedRows,User::TableExpectedRows'
Link $tables $days $guid
Link $tables $guid $dayLoop
$getDate=Add-Script $dayLoop 'Get DateTo' 'User::DateFrom,User::LoopCounter,User::ArchiwumPath,User::TableName,User::QuotedTable,User::QuotedColumn' 'User::CurrentDateFrom,User::CurrentDateTo,User::BatchNumber,User::DayExportedRows,User::CountSQL'
$count=Add-Sql $dayLoop 'Count records' 'CountSQL' 'ResultSetType_SingleRow' (,@('0','FileRecordCounter')) @(@('@DateFrom','User::CurrentDateFrom',[Data.DbType]::DateTime2),@('@DateTo','User::CurrentDateTo',[Data.DbType]::DateTime2))
$batches=$dayLoop.Executables.Add('STOCK:FORLOOP'); $batches.Name='Loop through 1000'; $batches.DelayValidation=$true; $batches.FailPackageOnFailure=$true
$batches.InitExpression='@[User::BatchNumber] = 0'; $batches.EvalExpression='@[User::FileRecordCounter] > 0'; $batches.AssignExpression='@[User::FileRecordCounter] = @[User::FileRecordCounter] - 1000'
Link $dayLoop $getDate $count
Link $dayLoop $count $batches


$construct=Add-Script $batches 'Construct SQL' 'User::QuotedTable,User::QuotedColumn,User::OrderBy' 'User::SQLStatement'
$export=Add-Script $batches 'Export data to CSV' 'User::SQLStatement,User::OutputFile,User::CurrentDateFrom,User::CurrentDateTo,User::FileRecordCounter,User::TableName,User::CsvHeader' 'User::DayExportedRows,User::BatchNumber,User::TableExportedRows'

Link $batches $construct $export
$complete=Add-Script $dayLoop 'Complete day' 'User::DayExportedRows,User::QuotedTable,User::QuotedColumn,User::CurrentDateFrom,User::CurrentDateTo' 'User::TableExpectedRows'
Link $dayLoop $batches $complete
$finalize=Add-Script $tables 'Finalize table' 'User::OutputFile,User::TableName,User::TableExportedRows,User::TableExpectedRows' ''
Link $tables $dayLoop $finalize
$skeleton=Join-Path $PSScriptRoot 'package-skeleton.dtsx'
$app.SaveToXml($skeleton,$package,$null)
$xml=[xml](Get-Content -LiteralPath $skeleton -Raw)
$ns=New-Object Xml.XmlNamespaceManager($xml.NameTable); $ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
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
    $main=Get-Content -LiteralPath (Join-Path $root ('scripts\'+$definition.Name+'.cs')) -Raw
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
$xml.DocumentElement.SetAttribute('LastModifiedProductVersion','www.microsoft.com/SqlServer/Dts','17.0.1016.0')
if($CompatibilityTest) { $destination=Join-Path $PSScriptRoot 'compatibility-test.dtsx' } else { $destination=$packagePath }
$xml.Save($destination)
Write-Output ('Built '+$destination)
