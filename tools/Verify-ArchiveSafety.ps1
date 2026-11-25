param([switch]$SkipCancellation,[switch]$FKOnly,[switch]$LargeOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Script-Source.ps1')
$root=Split-Path $PSScriptRoot -Parent
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$runRoot='C:\ArchiveTest\Safety_'+$stamp
[void](New-Item -ItemType Directory -Path $runRoot)
& icacls.exe $runRoot /grant 'NT SERVICE\MSSQL$SSISARCHIVE22:(OI)(CI)M' | Out-Null
if($LASTEXITCODE -ne 0){throw 'Cannot grant test folder access'}
$artifacts=Join-Path $root ('artifacts/sql2022/safety-'+$stamp)
[void](New-Item -ItemType Directory -Path $artifacts)
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$server='Data Source=.\SSISARCHIVE22;Integrated Security=True;TrustServerCertificate=True'
$connection=New-Object Data.SqlClient.SqlConnection($server)
$connection.Open()
$checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:checks++}
function Sql([string]$database,[string]$text) {
 $connection.ChangeDatabase($database)
 $command=$connection.CreateCommand();$command.CommandTimeout=180;$command.CommandText=$text
 try {return $command.ExecuteScalar()}finally{$command.Dispose()}
}
function Fixture([string]$name) {
 $db='ArchiveSafety_'+$stamp+'_'+$name
 if($db -notmatch '^ArchiveSafety_[0-9_]+_[A-Za-z0-9]+$'){throw 'Unsafe fixture name'}
 [void](Sql master "CREATE DATABASE [$db];")
 [void](Sql $db "CREATE SCHEMA Archive;")
 [void](Sql $db "CREATE SCHEMA Demo;")
 [void](Sql $db @'
CREATE TABLE Archive.ArchiveJobs(Id int IDENTITY PRIMARY KEY,DatabaseName nvarchar(128),TableName nvarchar(257),
 DateColumn nvarchar(128),ArchiveOlderThanDays int,LastSuccesProcessedAt datetime2(7),LastProcessedAt datetime2(7),LastProcessedStatus nvarchar(16),ErrorMessage nvarchar(max));
CREATE TABLE Archive.ArchiveJobRelations(Id int IDENTITY PRIMARY KEY,DatabaseName nvarchar(128),ParentTable nvarchar(257),ChildTable nvarchar(257),ParentKeyColumn sysname,ChildKeyColumn sysname);
CREATE TABLE Demo.Orders(Id int PRIMARY KEY,CreatedAt datetime2 NOT NULL,Payload nvarchar(80));
CREATE TABLE Demo.Lines(Id int PRIMARY KEY,OrderId int NOT NULL REFERENCES Demo.Orders(Id),Payload nvarchar(80));
CREATE TABLE Demo.Details(Id int PRIMARY KEY,LineId int NOT NULL REFERENCES Demo.Lines(Id),Payload nvarchar(80));
CREATE TABLE Demo.Events(Id int PRIMARY KEY,CreatedAt datetime2 NOT NULL);
INSERT Demo.Orders VALUES(1,'20230103','old-one'),(2,'20230103','old-two'),(3,'20230103','old-three'),(4,GETDATE(),'keep');
INSERT Demo.Lines VALUES(101,1,'a'),(102,1,'b'),(103,2,'c'),(104,4,'keep');
INSERT Demo.Details VALUES(201,101,'a'),(202,102,'b'),(203,103,'c'),(204,104,'keep');
INSERT Demo.Events VALUES(1,'20230103'),(2,GETDATE());
INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
 VALUES(DB_NAME(),'Demo.Orders','CreatedAt',30),(DB_NAME(),'Demo.Events','CreatedAt',30);
INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
 VALUES(DB_NAME(),'Demo.Orders','Demo.Lines','Id','OrderId'),(DB_NAME(),'Demo.Lines','Demo.Details','Id','LineId');
'@)
 $archive=Join-Path $runRoot $name
 [void](New-Item -ItemType Directory -Path $archive)
 return @{Db=$db;Root=$archive;Name=$name}
}
function Deploy([string]$fault) {
 $path=Join-Path $artifacts ($fault+'.ispac')
 Copy-Item (Join-Path $root 'artifacts/sql2022/Archive.Sql2022.ispac') $path -Force
 if($fault -ne 'Clean') {
  $target=switch($fault){'Write'{'Write batch to CSV'} 'ChildZip'{'Verify ZIP integrity'} 'AfterZip'{'Collect archive member deletion'} 'AfterDelete'{'Finalize successful archives'} 'Collision'{'Publish verified archive'} 'Cancel'{'Write batch to CSV'} 'AddFK'{'Prepare group deletion'}}
  $injection=switch($fault){
   'Write' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Orders" && Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value)>=1) throw new IOException("Injected export interruption");'}
   'ChildZip' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Lines") throw new IOException("Injected child ZIP failure");'}
   'AfterZip' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Orders") throw new IOException("Injected interruption after verified ZIP publication");'}
   'AfterDelete' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Orders") throw new IOException("Injected interruption after delete commit");'}
   'Collision' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Orders") File.Copy(Convert.ToString(Dts.Variables["User::ZipWorkingFile"].Value),Convert.ToString(Dts.Variables["User::ZipFile"].Value));'}
   'Cancel' {'if (Convert.ToString(Dts.Variables["User::TableName"].Value)=="Demo.Orders" && Convert.ToInt64(Dts.Variables["User::BatchNumber"].Value)==1) System.Threading.Thread.Sleep(30000);'}
   'AddFK' {'if (Convert.ToString(Dts.Variables["User::ParentTableName"].Value)=="Demo.Orders") { bool again=false; Dts.Events.FireInformation(0,"SafetyTest","PAUSED BEFORE FK REFRESH","",0,ref again); System.Threading.Thread.Sleep(10000); }'}
  }
  $zip=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Update)
  try {
   $entry=$zip.GetEntry('Package.dtsx');$reader=New-Object IO.StreamReader($entry.Open())
   try {$xml=[xml]$reader.ReadToEnd()}finally{$reader.Dispose()}
   $ns=New-Object Xml.XmlNamespaceManager($xml.NameTable);$ns.AddNamespace('D','www.microsoft.com/SqlServer/Dts')
   $script=$xml.SelectSingleNode('//D:Executable[@D:ObjectName="'+$target+'"]/D:ObjectData/ScriptProject',$ns)
   $item=$script.SelectSingleNode('ProjectItem[@Name="ScriptMain.cs"]');$source=$item.InnerText
   $pattern='private void ExecuteJobStep\(\)\s*\{'
   Assert ([regex]::IsMatch($source,$pattern)) ('Missing injection point: '+$target)
   $source=[regex]::Replace($source,$pattern,('$0'+[Environment]::NewLine+$injection),1)
   $access=Get-ScriptVariableAccess $source
   $script.SetAttribute('ReadOnlyVariables',$access.Read);$script.SetAttribute('ReadWriteVariables',$access.Write)
   $cs=Join-Path $artifacts ($fault+'.cs');$dll=Join-Path $artifacts ($fault+'.dll')
   [IO.File]::WriteAllText($cs,$source)
   $public='C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\IDE\PublicAssemblies\SSIS\160'
   & 'C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\Roslyn\csc.exe' /nologo /target:library "/out:$dll" "/reference:$public\Microsoft.SqlServer.ManagedDTS.dll" "/reference:$public\Microsoft.SqlServer.ScriptTask.dll" /reference:System.Data.dll $cs
   if($LASTEXITCODE -ne 0){throw 'Fault injection compilation failed'}
   $item.InnerText='';[void]$item.AppendChild($xml.CreateCDataSection($source))
   $script.SelectSingleNode('BinaryItem').InnerText=[Convert]::ToBase64String([IO.File]::ReadAllBytes($dll))
   $entry.Delete();$writer=New-Object IO.StreamWriter($zip.CreateEntry('Package.dtsx').Open())
   try{$writer.Write($xml.OuterXml)}finally{$writer.Dispose()}
  } finally{$zip.Dispose()}
 }
 [void](Sql SSISDB "IF NOT EXISTS(SELECT 1 FROM catalog.folders WHERE name=N'ArchiveSafetyTests') EXEC catalog.create_folder @folder_name=N'ArchiveSafetyTests';")
 $command=$connection.CreateCommand();$command.CommandTimeout=120
 $command.CommandText="EXEC catalog.deploy_project @folder_name=N'ArchiveSafetyTests',@project_name=N'Archive.Sql2022',@project_stream=@bytes;"
 [void]$command.Parameters.Add('@bytes',[Data.SqlDbType]::VarBinary,-1);$command.Parameters['@bytes'].Value=[IO.File]::ReadAllBytes($path)
 try{[void]$command.ExecuteNonQuery()}finally{$command.Dispose()}
}
function Execute($fixture,[int]$expected=7,[bool]$async=$false,[int]$limit=2) {
 $connection.ChangeDatabase('SSISDB');$command=$connection.CreateCommand();$command.CommandTimeout=180
 $command.CommandText=@'
DECLARE @execution bigint;
EXEC catalog.create_execution @folder_name=N'ArchiveSafetyTests',@project_name=N'Archive.Sql2022',@package_name=N'Package.dtsx',@execution_id=@execution OUTPUT;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ConnectionString',@parameter_value=@connection;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveJobsTable',@parameter_value=@jobs;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveJobRelationsTable',@parameter_value=@relations;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveRoot',@parameter_value=@root;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'MaxRecordsPerCsv',@parameter_value=@limit;
EXEC catalog.set_execution_parameter_value @execution_id=@execution,@object_type=50,@parameter_name=N'SYNCHRONIZED',@parameter_value=@sync;
EXEC catalog.start_execution @execution_id=@execution;
SELECT @execution;
'@
 foreach($p in @(@('@connection',($server+';Initial Catalog='+$fixture.Db)),@('@jobs',($fixture.Db+'.Archive.ArchiveJobs')),@('@relations',($fixture.Db+'.Archive.ArchiveJobRelations')),@('@root',$fixture.Root))) {
  [void]$command.Parameters.Add($p[0],[Data.SqlDbType]::NVarChar,4000);$command.Parameters[$p[0]].Value=$p[1]
 }
 [void]$command.Parameters.Add('@limit',[Data.SqlDbType]::Int);$command.Parameters['@limit'].Value=$limit
 [void]$command.Parameters.Add('@sync',[Data.SqlDbType]::Bit);$command.Parameters['@sync'].Value=!$async
 try{$execution=$command.ExecuteScalar()}finally{$command.Dispose()}
 if(!$async){CheckExecution $execution $expected}
 Write-Host ($fixture.Name+': execution '+$execution+' expected='+$expected)
 return $execution
}
function CheckExecution($execution,$expected){
 $status=Sql SSISDB "SELECT status FROM catalog.executions WHERE execution_id=$execution;"
 if($status -ne $expected){
  $connection.ChangeDatabase('SSISDB');$cmd=$connection.CreateCommand();$cmd.CommandText="SELECT TOP(6) message FROM catalog.operation_messages WHERE operation_id=$execution AND message_type=120 ORDER BY operation_message_id DESC;"
  $r=$cmd.ExecuteReader();try{while($r.Read()){Write-Host $r.GetString(0)}}finally{$r.Dispose();$cmd.Dispose()}
  throw "Execution $execution status=$status expected=$expected"
 }
 Assert ((Sql SSISDB "SELECT COUNT(*) FROM catalog.operation_messages WHERE operation_id=$execution AND (message LIKE '%deadlock%' OR message LIKE '%locks timed out%');") -eq 0) 'SSIS variable deadlock'
}
function SourceCount($f){return [int](Sql $f.Db 'SELECT (SELECT COUNT(*) FROM Demo.Orders)+(SELECT COUNT(*) FROM Demo.Lines)+(SELECT COUNT(*) FROM Demo.Details);')}
function ZipFiles($f){return @(Get-ChildItem $f.Root -Recurse -Filter '*.zip')}
function Hashes($f){$hashes=@{};foreach($file in (ZipFiles $f)){$hashes[$file.FullName]=(Get-FileHash $file.FullName -Algorithm SHA256).Hash};return $hashes}
function Unchanged($hashes){foreach($path in $hashes.Keys){Assert (Test-Path -LiteralPath $path) ('Deleted old ZIP: '+$path);Assert ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $hashes[$path]) ('Changed old ZIP: '+$path)}}
function ZipIds($path){
 $archive=[IO.Compression.ZipFile]::OpenRead($path);$ids=New-Object 'System.Collections.Generic.List[int]'
 try{foreach($entry in $archive.Entries){if(!$entry.Name.EndsWith('.csv')){continue};$r=New-Object IO.StreamReader($entry.Open(),[Text.Encoding]::UTF8);try{[void]$r.ReadLine();while(($line=$r.ReadLine()) -ne $null){if($line.Length -gt 0){$ids.Add([int]($line.Split(';')[0].Trim('"')))}}}finally{$r.Dispose()}}}finally{$archive.Dispose()}
 return ($ids | Sort-Object)
}
function ArchivePath($f,$table,$suffix=''){return (Join-Path $f.Root ($f.Db+'\Demo.'+$table+'\2023\styczen\2023_01_03'+$suffix+'.zip'))}
function AddLate($f,[int]$id){[void](Sql $f.Db "INSERT Demo.Orders VALUES($id,'20230103','late');INSERT Demo.Lines VALUES($($id+100),$id,'late');INSERT Demo.Details VALUES($($id+200),$($id+100),'late');")}
try {
 Deploy Clean
 if($LargeOnly){
  $f=Fixture Large
  [void](Sql $f.Db @'
CREATE TABLE Demo.ExportLoad(Id bigint PRIMARY KEY,CreatedAt datetime2 NOT NULL,Payload nvarchar(128) NOT NULL);
;WITH n AS(SELECT TOP(100000) ROW_NUMBER() OVER(ORDER BY(SELECT NULL)) AS Id FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT Demo.ExportLoad SELECT Id,CONVERT(datetime2,'20240614'),REPLICATE(N'0123456789ABCDEF',4) FROM n;
INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays) VALUES(DB_NAME(),'Demo.ExportLoad','CreatedAt',30);
'@)
  $timer=[Diagnostics.Stopwatch]::StartNew();[void](Execute $f 7 $false 1000)
  $bulkZip=Join-Path $f.Root ($f.Db+'\Demo.ExportLoad\2024\czerwiec\2024_06_14.zip')
  Assert ((Sql $f.Db 'SELECT COUNT(*) FROM Demo.ExportLoad;') -eq 0) 'Large table did not delete after export'
  $ids=@(ZipIds $bulkZip);Assert ($ids.Count -eq 100000 -and $ids[0] -eq 1 -and $ids[-1] -eq 100000) 'Large archive keys missing'
  $old=Hashes $f
  [void](Sql $f.Db "INSERT Demo.ExportLoad VALUES(100001,'20240614','late');")
  [void](Execute $f 7 $false 1000);Unchanged $old
  Assert (((ZipIds ($bulkZip.Replace('.zip','__PART2.zip'))) -join ',') -eq '100001') 'Large table late part is wrong'
  "PASS: $checks large-export checks, 100000 records, 100 CSV parts, late PART2, elapsedSeconds=$([Math]::Round($timer.Elapsed.TotalSeconds,1)). $artifacts" | Tee-Object -FilePath (Join-Path $artifacts 'results.txt')
  return
 }
 if(!$FKOnly){
 $f=Fixture Parts
 [void](Execute $f)
 Assert ((SourceCount $f) -eq 3) 'Normal archive did not delete the complete group'
 Assert (((ZipIds (ArchivePath $f Orders)) -join ',') -eq '1,2,3') 'Initial root ZIP content'
 Assert (((ZipIds (ArchivePath $f Lines)) -join ',') -eq '101,102,103') 'Initial child ZIP content'
 $old=Hashes $f
 $month=Split-Path (ArchivePath $f Orders)
 $legacy=Join-Path $month ('2023_01_03_retry_'+[guid]::NewGuid().ToString('N')+'.zip')
 Copy-Item (ArchivePath $f Orders) $legacy;$old[$legacy]=(Get-FileHash $legacy).Hash
 $stale=Join-Path $month '2023_01_03';[void](New-Item -ItemType Directory -Path $stale);Set-Content (Join-Path $stale stale.csv) 'STALE'
 AddLate $f 5
 [void](Execute $f)
 Unchanged $old
 Assert (((ZipIds (ArchivePath $f Orders '__PART2')) -join ',') -eq '5') 'PART2 must contain only the late row'
 Assert (!(Test-Path -LiteralPath $stale)) 'Old work folder was not cleaned'
 $old=Hashes $f;AddLate $f 6;[void](Execute $f);Unchanged $old
 Assert (((ZipIds (ArchivePath $f Orders '__PART3')) -join ',') -eq '6') 'PART3 not created'
 Copy-Item (ArchivePath $f Orders '__PART3') (ArchivePath $f Orders '__PART9')
 $old=Hashes $f;AddLate $f 7;[void](Execute $f);Unchanged $old
 Assert (((ZipIds (ArchivePath $f Orders '__PART10')) -join ',') -eq '7') 'Part number did not follow the maximum existing ZIP'

 foreach($fault in @('Write','ChildZip','AfterZip','AfterDelete','Collision')) {
  $f=Fixture $fault;Deploy $fault;[void](Execute $f 4)
  $count=SourceCount $f
  Assert ($count -eq $(if($fault -eq 'AfterDelete'){3}else{12})) ('Wrong source count after '+$fault)
  if($fault -eq 'Write'){
   Assert (!(Test-Path -LiteralPath (ArchivePath $f Orders))) 'Partial export published a ZIP'
   $work=Join-Path (Split-Path (ArchivePath $f Orders)) '2023_01_03'
   Assert (Test-Path -LiteralPath $work) 'Expected unfinished work folder'
   Set-Content (Join-Path $work archive.pending) 'PARTIAL'
  }
  $old=Hashes $f
  Deploy Clean;[void](Execute $f);Unchanged $old
  Assert ((SourceCount $f) -eq 3) ('Retry failed after '+$fault)
  if($fault -eq 'AfterDelete'){
   AddLate $f 5;[void](Execute $f);Unchanged $old
   Assert (((ZipIds (ArchivePath $f Orders '__PART2')) -join ',') -eq '5') 'Post-commit interruption lost the late part'
  }
  if($fault -in @('AfterZip','ChildZip','Collision')){
   Assert (Test-Path -LiteralPath (ArchivePath $f Orders '__PART2')) ('Retry did not preserve first ZIP for '+$fault)
  }
  Assert (@(Get-ChildItem $f.Root -Recurse -File | Where-Object {$_.Extension -eq '.csv' -or $_.Name -eq 'archive.pending'}).Count -eq 0) ('Work files remain after successful recovery '+$fault)
 }

 $f=Fixture Rollback
 [void](Sql $f.Db "CREATE TRIGGER Demo.FailDelete ON Demo.Orders INSTEAD OF DELETE AS THROW 50001,'Safety rollback test',1;")
 [void](Execute $f 4);Assert ((SourceCount $f) -eq 12) 'Group delete failure did not roll back child deletions'
 $old=Hashes $f;[void](Sql $f.Db 'DROP TRIGGER Demo.FailDelete;');[void](Execute $f);Unchanged $old
 Assert ((SourceCount $f) -eq 3) 'Retry after rollback failed'
 }

 foreach($rule in @('NO ACTION','CASCADE','SET NULL','SET DEFAULT')){
  $f=Fixture ($rule.Replace(' ',''))
  [void](Sql $f.Db ("CREATE TABLE Demo.Missing(Id int PRIMARY KEY,OrderId int NULL DEFAULT 4,CONSTRAINT FK_Missing FOREIGN KEY(OrderId) REFERENCES Demo.Orders(Id) ON DELETE "+$rule+"); INSERT Demo.Missing VALUES(1,1);"))
  [void](Execute $f 4)
  Assert ((SourceCount $f) -eq 12) ('Preflight changed source with '+$rule)
  Assert (!(Test-Path -LiteralPath (ArchivePath $f Orders))) ('Export started before missing-FK rejection '+$rule)
  $fkErrorText=Sql $f.Db 'SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;'
  Assert ($fkErrorText -like '*Missing relation*Demo*Missing*DeleteRule=*') ('Missing clear FK diagnostic '+$rule)
 }
 $f=Fixture Grandchild
 [void](Sql $f.Db "DELETE Archive.ArchiveJobRelations WHERE ChildTable='Demo.Details';")
 [void](Execute $f 4)
 Assert ((Sql $f.Db 'SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;') -like '*Demo*Lines*Demo*Details*') 'Missing grandchild was not reported'
 Assert ((SourceCount $f) -eq 12) 'Missing grandchild changed source'
 $f=Fixture EmptyChild
 [void](Sql $f.Db 'CREATE TABLE Demo.EmptyMissing(Id int PRIMARY KEY,OrderId int REFERENCES Demo.Orders(Id) ON DELETE CASCADE);')
 [void](Execute $f 4)
 Assert ((Sql $f.Db 'SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;') -like '*EmptyMissing*') 'Empty child was not checked'
 $f=Fixture Composite
 [void](Sql $f.Db 'ALTER TABLE Demo.Orders ADD Tenant int NOT NULL DEFAULT 1; ALTER TABLE Demo.Orders ADD CONSTRAINT UQ_Orders_Tenant UNIQUE(Id,Tenant);CREATE TABLE Demo.CompositeChild(Id int PRIMARY KEY,OrderId int,Tenant int,CONSTRAINT FK_Composite FOREIGN KEY(OrderId,Tenant) REFERENCES Demo.Orders(Id,Tenant));')
 [void](Sql $f.Db "INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn) VALUES(DB_NAME(),'Demo.Orders','Demo.CompositeChild','Id','OrderId'),(DB_NAME(),'Demo.Orders','Demo.CompositeChild','Tenant','Tenant');")
 [void](Execute $f 4)
 Assert ((Sql $f.Db 'SELECT ErrorMessage FROM Archive.ArchiveJobs WHERE Id=1;') -like '*Unsupported composite FK*') 'Composite FK was incorrectly treated as OR edges'

 $f=Fixture CaseMismatch
 [void](Sql $f.Db "UPDATE Archive.ArchiveJobRelations SET ParentTable='Demo.orders' WHERE ParentTable='Demo.Orders';")
 [void](Execute $f 4)
 Assert ((SourceCount $f) -eq 12) 'Incomplete plan caused by casing changed source'
 Assert (!(Test-Path -LiteralPath (ArchivePath $f Orders))) 'Incomplete plan was not rejected before export'

 $f=Fixture FolderGuard
 $work=Join-Path (Split-Path (ArchivePath $f Orders)) '2023_01_03';[void](New-Item -ItemType Directory -Path $work -Force)
 $insideZip=Join-Path $work 'keep.zip';[IO.File]::WriteAllBytes($insideZip,[byte[]](1,2,3,4))
 $protected=@{};$protected[$insideZip]=(Get-FileHash $insideZip).Hash
 [void](Execute $f 4);Unchanged $protected
 Assert ((SourceCount $f) -eq 12) 'Unexpected work-folder ZIP was not preserved safely'
 Remove-Item -LiteralPath $insideZip
 [void](Execute $f);Assert ((SourceCount $f) -eq 3) 'Recovery after safe folder rejection failed'

 $f=Fixture LateFK;Deploy AddFK;$execution=Execute $f 4 $true
 $deadline=(Get-Date).AddSeconds(30)
 do{
  $ready=Sql SSISDB "SELECT COUNT(*) FROM catalog.operation_messages WHERE operation_id=$execution AND message LIKE '%PAUSED BEFORE FK REFRESH%';"
  if($ready -gt 0){break};Start-Sleep -Milliseconds 100
 }while((Get-Date) -lt $deadline)
 Assert ($ready -gt 0) 'FK refresh fixture did not reach deletion boundary'
 [void](Sql $f.Db 'CREATE TABLE Demo.LateChild(Id int PRIMARY KEY,OrderId int REFERENCES Demo.Orders(Id) ON DELETE CASCADE);INSERT Demo.LateChild VALUES(1,1);')
 $deadline=(Get-Date).AddSeconds(40)
 do{$status=Sql SSISDB "SELECT status FROM catalog.executions WHERE execution_id=$execution;";if($status -notin @(2,5,8)){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $deadline)
 CheckExecution $execution 4
 Assert ((SourceCount $f) -eq 12) 'FK added after export was not detected before deletion'
 Assert ((Sql $f.Db 'SELECT COUNT(*) FROM Demo.LateChild;') -eq 1) 'Cascade deleted an unconfigured late child'
 $old=Hashes $f
 [void](Sql $f.Db "INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn) VALUES(DB_NAME(),'Demo.Orders','Demo.LateChild','Id','OrderId');")
 Deploy Clean;[void](Execute $f);Unchanged $old
 Assert ((Sql $f.Db 'SELECT COUNT(*) FROM Demo.LateChild;') -eq 0) 'Configured late child was not archived/deleted on retry'

 $f=Fixture Exclusive
 $holder=New-Object Data.SqlClient.SqlConnection($server);$holder.Open()
 try{
  $path=[IO.Path]::GetFullPath($f.Root).TrimEnd('\','/').ToUpperInvariant();$sha=[Security.Cryptography.SHA256]::Create()
  try{$resource='CSVArchive:'+([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($path)))).Replace('-','')}finally{$sha.Dispose()}
  $command=$holder.CreateCommand();$command.CommandText="DECLARE @r int;EXEC @r=master.sys.sp_getapplock @Resource=N'$resource',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=0;SELECT @r;"
  Assert ($command.ExecuteScalar() -ge 0) 'Could not hold competing run lock'
  [void](Execute $f 4)
  Assert ((SourceCount $f) -eq 12) 'Concurrent run changed source'
  Assert ((ZipFiles $f).Count -eq 0) 'Concurrent run published files'
 }finally{
  if($holder.State -eq 'Open'){
   $release=$holder.CreateCommand();$release.CommandText="DECLARE @r int;EXEC @r=master.sys.sp_releaseapplock @Resource=N'$resource',@LockOwner='Session';SELECT @r;"
   Assert ($release.ExecuteScalar() -ge 0) 'Conflicting run released another session lock'
   $release.Dispose()
  }
  $holder.Dispose()
 }
 [void](Execute $f);Assert ((SourceCount $f) -eq 3) 'Execution lock was not released'

 if(!$SkipCancellation){
  $f=Fixture Cancel;Deploy Cancel;$execution=Execute $f 3 $true
  $deadline=(Get-Date).AddSeconds(60);$work=Join-Path (Split-Path (ArchivePath $f Orders)) '2023_01_03'
  while(!(Test-Path -LiteralPath (Join-Path $work '2023_01_03_part1.csv')) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 200}
  Assert (Test-Path -LiteralPath $work) 'Cancellation fixture did not reach CSV export'
  [void](Sql SSISDB "EXEC catalog.stop_operation @operation_id=$execution;")
  $deadline=(Get-Date).AddSeconds(65)
  do{$status=Sql SSISDB "SELECT status FROM catalog.executions WHERE execution_id=$execution;";if($status -notin @(2,5,8)){break};Start-Sleep -Milliseconds 500}while((Get-Date) -lt $deadline)
  CheckExecution $execution 3
  Assert ((SourceCount $f) -eq 12) 'Actual cancellation deleted source rows'
  Deploy Clean;[void](Execute $f);Assert ((SourceCount $f) -eq 3) 'Retry after actual cancellation failed'
 }
 "PASS: $checks safety checks. Artifacts: $artifacts; source fixtures: ArchiveSafety_$stamp*; archive files: $runRoot" | Tee-Object -FilePath (Join-Path $artifacts 'results.txt')
} finally{$connection.Dispose()}
