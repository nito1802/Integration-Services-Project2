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
foreach($name in @('ConnectionString','ArchiveJobsConnectionString','ArchiveRoot')) {
    $valueNode=$current.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="'+$name+'"]/DTS:Property[@DTS:Name="ParameterValue"]',$currentNs)
    if($valueNode) { $currentValues[$name]=$valueNode.InnerText }
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
$package.VersionBuild=$package.VersionBuild+1
$package.MaxConcurrentExecutables=1
$package.TransactionOption=[Microsoft.SqlServer.Dts.Runtime.DTSTransactionOption]::NotSupported
$package.DelayValidation=$true
$package.Description='CSV archive: ArchiveJobs -> tables -> days -> batches of 1000 -> SetTableStatus. Direct CSV output, no explicit transactions. Source tables are read only.'
$package.Variables.Remove('User::SQLStatement')
function Add-Variable($name,$value) { [void]$package.Variables.Add($name,$false,'User',$value) }
foreach($name in @('Tables')) { Add-Variable $name (New-Object object) }
foreach($name in @('TableName','ColumnDate','ArchiwumPath','BeginScript','SQLStatement','FolderFullPath','OutputFile','AddNumber','QuotedTable','QuotedColumn','OrderBy','DatabaseName','JobError','CsvHeader')) { Add-Variable $name '' }
foreach($name in @('Days','DaysCounter','LoopCounter','ArchiveJobId','FailedJobs')) { Add-Variable $name ([int]0) }
Add-Variable 'BatchNumber' ([long]0)
foreach($name in @('DateFrom','DateTo','CurrentDateFrom','CurrentDateTo')) { Add-Variable $name ([datetime]'2000-01-01') }
foreach($name in @('JobActive','JobFailed','BatchHasRows')) { Add-Variable $name $false }
$archiveRoot=[IO.Path]::GetDirectoryName([string]$package.Parameters['OutputFile'].Value)
foreach($obsolete in @('TableName','DateColumn','OlderThanDays','OutputFile')) { [void]$package.Parameters.Remove($obsolete) }
$p=$package.Parameters.Add('ArchiveRoot',[TypeCode]::String); $p.Value=$archiveRoot
if($currentValues.ContainsKey('ConnectionString')) { $package.Parameters['ConnectionString'].Value=$currentValues['ConnectionString'] }
if($currentValues.ContainsKey('ArchiveRoot')) { $package.Parameters['ArchiveRoot'].Value=$currentValues['ArchiveRoot'] }
$p=$package.Parameters.Add('ArchiveJobsConnectionString',[TypeCode]::String)
$p.Value=if($currentValues.ContainsKey('ArchiveJobsConnectionString')) { $currentValues['ArchiveJobsConnectionString'] } else { $package.Parameters['ConnectionString'].Value }
$p.Description='Connection to the database containing Archive.ArchiveJobs (job configuration and processing status).'
$connection=$package.Connections.Add('ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$connection.Name='ArchiveDb'
$connection.SetExpression('ConnectionString','@[$Package::ConnectionString]')
$connection.Properties['RetainSameConnection'].SetValue($connection,$true)
$connection.DelayValidation=$true
$statusConnection=$package.Connections.Add('ADO.NET:System.Data.SqlClient.SqlConnection, System.Data, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
$statusConnection.Name='ArchiveJobsDb'
$statusConnection.SetExpression('ConnectionString','@[$Package::ArchiveJobsConnectionString]')
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
$getSettings=Add-Script $package 'Get Archive Jobs' '' 'User::Tables'
$tables=$package.Executables.Add('STOCK:FOREACHLOOP'); $tables.Name='Foreach Loop Container'; $tables.DelayValidation=$true; $tables.FailPackageOnFailure=$true
$tables.ForEachEnumerator=$app.ForEachEnumeratorInfos['Foreach ADO Enumerator'].CreateNew()
$tables.ForEachEnumerator.InnerObject.DataObjectVariable='User::Tables'
foreach($entry in @(@('ArchiveJobId',0),@('DatabaseName',1),@('TableName',2),@('Days',3),@('ColumnDate',4))) { $mapping=$tables.VariableMappings.Add(); $mapping.VariableName='User::'+$entry[0]; $mapping.ValueIndex=$entry[1] }
Link $package $getSettings $tables
$startJob=Add-Script $tables 'Start archive job' '$Package::ArchiveRoot,User::DatabaseName' 'User::ArchiwumPath'
$begin=Add-Script $tables 'BeginScript' 'User::TableName,User::ColumnDate,User::Days' 'User::BeginScript,User::LoopCounter,User::QuotedTable,User::QuotedColumn,User::OrderBy'
$days=Add-Script $tables 'Count days diff' 'User::BeginScript,User::Days' 'User::DaysCounter,User::DateFrom,User::DateTo'
$dayLoop=$tables.Executables.Add('STOCK:FORLOOP'); $dayLoop.Name='For Loop Container'; $dayLoop.DelayValidation=$true; $dayLoop.FailPackageOnFailure=$true
$dayLoop.InitExpression='@[User::LoopCounter] = 0'; $dayLoop.EvalExpression='!@[User::JobFailed] && @[User::LoopCounter] < @[User::DaysCounter]'; $dayLoop.AssignExpression='@[User::LoopCounter] = @[User::LoopCounter] + 1'
Link $tables $startJob $begin
Link $tables $begin $days
$guid=Add-Script $tables 'GetGuid' 'System::StartTime,User::ArchiwumPath,User::TableName,User::QuotedTable' 'User::FolderFullPath,User::AddNumber,User::OutputFile,User::CsvHeader'
Link $tables $days $guid
Link $tables $guid $dayLoop
$getDate=Add-Script $dayLoop 'Get DateTo' 'User::DateFrom,User::LoopCounter' 'User::CurrentDateFrom,User::CurrentDateTo,User::BatchNumber,User::BatchHasRows'
$batches=$dayLoop.Executables.Add('STOCK:FORLOOP'); $batches.Name='Loop through 1000'; $batches.DelayValidation=$true; $batches.FailPackageOnFailure=$true
$batches.InitExpression='@[User::BatchNumber] = 0'; $batches.EvalExpression='!@[User::JobFailed] && @[User::BatchHasRows]'
Link $dayLoop $getDate $batches


$construct=Add-Script $batches 'Construct SQL' 'User::QuotedTable,User::QuotedColumn,User::OrderBy' 'User::SQLStatement'
$export=Add-Script $batches 'Export data to CSV' 'User::SQLStatement,User::OutputFile,User::CurrentDateFrom,User::CurrentDateTo,User::TableName,User::CsvHeader' 'User::BatchNumber,User::BatchHasRows'

Link $batches $construct $export
$setStatus=Add-Script $tables 'SetTableStatus' '' ''
Link $tables $dayLoop $setStatus
$summary=Add-Script $package 'Archive summary' '' ''
Link $package $tables $summary
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
if (!$CompatibilityTest) {
    $projectFile=Join-Path $project 'Integration Services Project2.dtproj'
    $projectXml=[xml](Get-Content -LiteralPath $projectFile -Raw)
    $projectNs=New-Object Xml.XmlNamespaceManager($projectXml.NameTable)
    $projectNs.AddNamespace('SSIS','www.microsoft.com/SqlServer/SSIS')
    foreach($parameterNode in @($projectXml.SelectNodes('//SSIS:PackageMetaData/SSIS:Parameters/SSIS:Parameter',$projectNs))) {
        if($parameterNode.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS') -notin @('ConnectionString','ArchiveJobsConnectionString','ArchiveRoot')) {
            [void]$parameterNode.ParentNode.RemoveChild($parameterNode)
        }
    }
    $parameterList=$projectXml.SelectSingleNode('//SSIS:PackageMetaData/SSIS:Parameters',$projectNs)
    $jobsParameter=$parameterList.SelectSingleNode('SSIS:Parameter[@SSIS:Name="ArchiveJobsConnectionString"]',$projectNs)
    if(!$jobsParameter) {
        $jobsParameter=$parameterList.SelectSingleNode('SSIS:Parameter[@SSIS:Name="ConnectionString"]',$projectNs).CloneNode($true)
        $jobsParameter.SetAttribute('Name','www.microsoft.com/SqlServer/SSIS','ArchiveJobsConnectionString')
        $jobsParameter.SelectSingleNode('SSIS:Properties/SSIS:Property[@SSIS:Name="ID"]',$projectNs).InnerText=[string]$package.Parameters['ArchiveJobsConnectionString'].ID
        [void]$parameterList.AppendChild($jobsParameter)
    }
    foreach($parameterName in @('ConnectionString','ArchiveJobsConnectionString','ArchiveRoot')) {
        $projectXml.SelectSingleNode('//SSIS:PackageMetaData/SSIS:Parameters/SSIS:Parameter[@SSIS:Name="'+$parameterName+'"]/SSIS:Properties/SSIS:Property[@SSIS:Name="Value"]',$projectNs).InnerText=[string]$package.Parameters[$parameterName].Value
    }
    $projectXml.Save($projectFile)
}
Write-Output ('Built '+$destination)
