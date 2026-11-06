param([string]$Path)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$Path){$Path=Join-Path $root 'artifacts/sql2022/Archive.Sql2022.ispac'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($Path)
try {
 function Read-Entry($name) { $reader=New-Object IO.StreamReader($zip.GetEntry($name).Open()); try{$reader.ReadToEnd()}finally{$reader.Dispose()} }
 $manifest=[xml](Read-Entry '@Project.manifest')
 $mn=New-Object Xml.XmlNamespaceManager($manifest.NameTable); $mn.AddNamespace('SSIS','www.microsoft.com/SqlServer/SSIS')
 if($manifest.SelectSingleNode('//SSIS:Property[@SSIS:Name="TargetServerVersion"]',$mn).InnerText -ne '160'){throw 'ISPAC does not target SQL Server 2022'}
 if($manifest.SelectSingleNode('/SSIS:Project/SSIS:Properties/SSIS:Property[@SSIS:Name="Name"]',$mn).InnerText -ne 'Archive.Sql2022'){throw 'Unexpected deployment project name'}
 $package=[xml](Read-Entry 'Package.dtsx')
 $scripts=@($package.SelectNodes('//ScriptProject'))
 if(!$scripts.Count){throw 'No Script Tasks found'}
 foreach($script in $scripts) {
  if($script.VSTAMajorVersion -ne '16'){throw 'Wrong Script Task version'}
  $assembly=[Reflection.Assembly]::ReflectionOnlyLoad([Convert]::FromBase64String($script.SelectSingleNode('BinaryItem').InnerText))
  $refs=@($assembly.GetReferencedAssemblies() | Where-Object {$_.Name -in @('Microsoft.SqlServer.ManagedDTS','Microsoft.SqlServer.ScriptTask')})
  if($refs.Count -ne 2 -or @($refs | Where-Object {$_.Version.Major -ne 16}).Count){throw 'Script DLL references incorrect SSIS runtime'}
  foreach($item in $script.SelectNodes('ProjectItem')) {if($item.Name -like '*.csproj' -and $item.InnerText -match 'Version=17\.0\.0\.0|SSIS_ST170'){throw 'Embedded script project still targets 2025'}}
 }
 $dn=New-Object Xml.XmlNamespaceManager($package.NameTable); $dn.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
 $dn.AddNamespace('SQLTask','www.microsoft.com/sqlserver/dts/tasks/sqltask')
 $managers=@($package.SelectNodes('/DTS:Executable/DTS:ConnectionManagers/DTS:ConnectionManager',$dn))
 if($managers.Count -ne 1 -or $managers[0].GetAttribute('ObjectName','www.microsoft.com/SqlServer/Dts') -ne 'ArchiveDb'){throw 'Expected one shared ArchiveDb connection manager'}
 $id=$managers[0].GetAttribute('DTSID','www.microsoft.com/SqlServer/Dts')
 if($managers[0].SelectSingleNode('DTS:PropertyExpression[@DTS:Name="ConnectionString"]',$dn).InnerText -ne '@[$Package::ConnectionString]'){throw 'Shared connection does not use package ConnectionString'}
 if($managers[0].SelectSingleNode('DTS:ObjectData/DTS:ConnectionManager',$dn).GetAttribute('Retain','www.microsoft.com/SqlServer/Dts') -ne 'True'){throw 'Shared connection must retain the SQL session'}
 foreach($task in $package.SelectNodes('//SQLTask:SqlTaskData',$dn)){if($task.GetAttribute('Connection','www.microsoft.com/sqlserver/dts/tasks/sqltask') -ne $id){throw 'SQL task does not use shared ArchiveDb'}}
 $connection=$package.SelectSingleNode('//DTS:PackageParameter[@DTS:ObjectName="ConnectionString"]/DTS:Property[@DTS:Name="ParameterValue"]',$dn).InnerText
 if($connection -ne 'Data Source=.;Integrated Security=True;TrustServerCertificate=True'){throw 'Unexpected deployment connection default'}
 $result=@("PASS: ISPAC TargetServerVersion=160 (SQL Server 2022).","PASS: $($scripts.Count) Script Tasks: VSTA 16 and compiled references ManagedDTS/ScriptTask 16.0.0.0.",'PASS: no SQL Server 2025 references in embedded script projects; safe connection defaults.',('SHA256: '+(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash))
 $result+='PASS: one retained ArchiveDb connection, controlled by package ConnectionString, used by all SQL tasks.'
 $result | Set-Content (Join-Path $root 'artifacts/sql2022/compatibility.txt') -Encoding UTF8
 $result
} finally {$zip.Dispose()}
