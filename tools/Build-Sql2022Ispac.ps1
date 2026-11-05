param([string]$VisualStudioRoot='C:\Program Files\Microsoft Visual Studio\18\Insiders')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$source=Join-Path $root 'Integration Services Project2'
$destination=Join-Path $root 'artifacts/sql2022/project'
[void](New-Item -ItemType Directory -Path $destination -Force)
$defaults=@{ConnectionString='Data Source=.;Integrated Security=True;TrustServerCertificate=True';ArchiveJobsTable='Archive.ArchiveJobs';ArchiveRoot='C:\ArchiveTest';MaxRecordsPerCsv='1000'}
$package=[xml](Get-Content (Join-Path $source 'Package.dtsx') -Raw)
$ns=New-Object Xml.XmlNamespaceManager($package.NameTable); $ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
foreach($script in $package.SelectNodes('//ScriptProject')) { if($script.VSTAMajorVersion -ne '16') { throw 'Rebuild package with Build-Package.ps1 -TargetServerVersion SQLServer2022 first.' } }
foreach($name in $defaults.Keys) {
 $package.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="'+$name+'"]/DTS:Property[@DTS:Name="ParameterValue"]',$ns).InnerText=$defaults[$name]
}
foreach($manager in $package.SelectNodes('//DTS:ConnectionManager/DTS:ObjectData/DTS:ConnectionManager',$ns)) { [void]$manager.SetAttribute('ConnectionString','www.microsoft.com/SqlServer/Dts',$defaults.ConnectionString) }
$package.Save((Join-Path $destination 'Package.dtsx'))
$project=[xml](Get-Content (Join-Path $source 'Integration Services Project2.dtproj') -Raw)
$pn=New-Object Xml.XmlNamespaceManager($project.NameTable); $pn.AddNamespace('SSIS','www.microsoft.com/SqlServer/SSIS')
$project.SelectSingleNode('//SSIS:Project/SSIS:Properties/SSIS:Property[@SSIS:Name="Name"]',$pn).InnerText='Archive.Sql2022'
foreach($parameter in $project.SelectNodes('//SSIS:Parameter',$pn)) {
 $name=$parameter.GetAttribute('Name','www.microsoft.com/SqlServer/SSIS')
 if($defaults.ContainsKey($name)) { $value=$parameter.SelectSingleNode('SSIS:Properties/SSIS:Property[@SSIS:Name="Value"]',$pn); if($value){$value.InnerText=$defaults[$name]} }
}
foreach($target in $project.SelectNodes('//TargetServerVersion')) { $target.InnerText='SQLServer2022' }
$projectPath=Join-Path $destination 'Archive.Sql2022.dtproj'
$project.Save($projectPath)
Copy-Item (Join-Path $source 'Project.params'),(Join-Path $source 'Integration Services Project2.database') -Destination $destination
$log=Join-Path (Split-Path $destination -Parent) 'build.log'
$arguments='"'+$projectPath+'" /Rebuild Development /Out "'+$log+'"'
$process=Start-Process -FilePath (Join-Path $VisualStudioRoot 'Common7/IDE/devenv.com') -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
if($process.ExitCode -ne 0) { throw "SSDT build failed. See $log" }
$ispac=Get-ChildItem (Join-Path $destination 'bin') -Filter '*.ispac' -Recurse | Select-Object -First 1
if(!$ispac) { throw 'SSDT did not produce ISPAC.' }
$output=Join-Path (Split-Path $destination -Parent) 'Archive.Sql2022.ispac'
Copy-Item -LiteralPath $ispac.FullName -Destination $output -Force
Write-Output "ISPAC: $output"
Write-Output "Build log: $log"
