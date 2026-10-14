# Executes production ScriptMain sources with a small SSIS host substitute and real isolated LocalDB connections.
param([switch]$FailuresOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB test' }
$build=Join-Path $PSScriptRoot '.script-build/delete-test'
[void](New-Item -ItemType Directory -Path $build -Force)
$stub=@"
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
namespace Microsoft.SqlServer.Dts.Runtime { public enum DTSExecResult { Success, Failure } }
namespace Microsoft.SqlServer.Dts.Tasks.ScriptTask {
 public class SSISScriptTaskEntryPointAttribute : Attribute { }
 public class VSTARTScriptObjectModelBase { public ProbeDts Dts { get; set; } }
}
public class ProbeVariable { public object Value { get; set; } }
public class ProbeConnection {
 public SqlConnection Connection;
 public object AcquireConnection(object transaction) { return Connection; }
 public void ReleaseConnection(SqlConnection connection) { }
}
public class ProbeEvents {
 public void FireInformation(int code,string source,string message,string help,int context,ref bool again) { }
 public void FireWarning(int code,string source,string message,string help,int context) { }
 public void FireError(int code,string source,string message,string help,int context) { throw new Exception(message); }
}
public class ProbeDts {
 public Dictionary<string,ProbeVariable> Variables = new Dictionary<string,ProbeVariable>();
 public Dictionary<string,ProbeConnection> Connections = new Dictionary<string,ProbeConnection>();
 public ProbeEvents Events = new ProbeEvents();
 public object Transaction;
 public int TaskResult;
}
"@
$stubPath=Join-Path $build 'Stub.cs'; [IO.File]::WriteAllText($stubPath,$stub)
$files=@($stubPath)
$common=Get-Content -LiteralPath (Join-Path $root 'scripts/Common.cs') -Raw
$names=@('Get Archive Jobs','Start archive job','BeginScript','Count days diff','GetGuid','Get DateTo','Construct SQL','Export data to CSV','Delete exported batch','SetTableStatus')
for($i=0;$i -lt $names.Count;$i++) {
 $main=Get-Content -LiteralPath (Join-Path $root ('scripts/'+$names[$i]+'.cs')) -Raw
 $path=Join-Path $build ('Task'+$i+'.cs')
 [IO.File]::WriteAllText($path,$common.Replace('__NAMESPACE__',('DeleteProbe'+$i)).Replace('// __MAIN__',$main))
 $files+=$path
}
# A controlled write error proves that Delete exported batch is skipped by Run.
$main=Get-Content -LiteralPath (Join-Path $root 'scripts/Export data to CSV.cs') -Raw
$main=$main.Replace('writer.WriteLine();','writer.WriteLine(); throw new IOException("Injected CSV write failure.");')
$path=Join-Path $build 'WriteFailure.cs'
[IO.File]::WriteAllText($path,$common.Replace('__NAMESPACE__','WriteFailureProbe').Replace('// __MAIN__',$main)); $files+=$path
$dll=Join-Path $build 'DeleteProbe.dll'
& 'C:/Program Files/Microsoft Visual Studio/18/Insiders/MSBuild/Current/Bin/Roslyn/csc.exe' /nologo /target:library "/out:$dll" /reference:System.Data.dll $files
if($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
Add-Type -Path $dll
$source=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
$status=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
function Invoke-Step([int]$Index) {
 $task=New-Object ('DeleteProbe'+$Index+'.ScriptMain'); $task.Dts=$script:dts; $task.Main()
}
function Read-Scalar([string]$Sql) { $command=$source.CreateCommand(); $command.CommandText=$Sql; return $command.ExecuteScalar() }
function Run-Job([int]$Id,[string]$Table,[string]$Column,[string]$Mode='Normal') {
 $dts.Variables['User::ArchiveJobId'].Value=$Id
 $dts.Variables['User::DatabaseName'].Value=$config.Database
 $dts.Variables['User::TableName'].Value=$Table
 $dts.Variables['User::ColumnDate'].Value=$Column
 $dts.Variables['User::Days'].Value=1
 foreach($i in @(1,2,3,4)) { Invoke-Step $i }
 $days=[int]$dts.Variables['User::DaysCounter'].Value
 if($days -gt 5000) { throw 'Unexpected range' }
 for($day=0;$day -lt $days -and !$dts.Variables['User::JobFailed'].Value;$day++) {
  $dts.Variables['User::LoopCounter'].Value=$day; Invoke-Step 5
  $batches=0
  while($dts.Variables['User::BatchHasRows'].Value -and !$dts.Variables['User::JobFailed'].Value) {
   if(++$batches -gt 10) { throw 'Batch loop did not finish' }
   Invoke-Step 6
   if($Mode -eq 'WriteFailure') {
    $task=New-Object WriteFailureProbe.ScriptMain; $task.Dts=$dts; $task.Main()
   } else { Invoke-Step 7 }
   if($Mode -eq 'ExactBatch' -and $day -eq 0 -and $batches -eq 1) {
    $command=$source.CreateCommand()
    $command.CommandText="INSERT dbo.ExactBatch VALUES(-1,DATEADD(day,-3,CONVERT(date,GETDATE())),N'new row');"
    [void]$command.ExecuteNonQuery()
   }
   Invoke-Step 8
   if($Mode -eq 'ExactBatch' -and $day -eq 0 -and $batches -eq 1) {
    if((Read-Scalar 'SELECT COUNT(*) FROM dbo.ExactBatch WHERE Id=-1;') -ne 1) { throw 'Delete removed a row outside the exported batch' }
   }
  }
 }
 Invoke-Step 9
 return $dts.Variables['User::OutputFile'].Value
}
try {
 $source.Open(); $status.Open()
 $script:dts=New-Object ProbeDts
 $values=@{Tables=(New-Object object);BatchKeys=(New-Object object);JobActive=$false;JobFailed=$false;JobError='';FailedJobs=0;ArchiveJobId=0;DatabaseName='';TableName='';ColumnDate='';Days=1;DaysCounter=0;DateFrom=[datetime]::Now;DateTo=[datetime]::Now;CurrentDateFrom=[datetime]::Now;CurrentDateTo=[datetime]::Now;LoopCounter=0;BatchNumber=[long]0;BatchHasRows=$false;KeyColumns='';CsvHeader='';FolderFullPath='';AddNumber='';OutputFile='';ArchiwumPath='';BeginScript='';SQLStatement=''}
 foreach($name in $values.Keys) { $v=New-Object ProbeVariable; $v.Value=$values[$name]; $dts.Variables.Add(('User::'+$name),$v) }
 $v=New-Object ProbeVariable; $v.Value=[datetime]::Now; $dts.Variables.Add('System::StartTime',$v)
 $v=New-Object ProbeVariable; $v.Value=$config.ArchiveRoot; $dts.Variables.Add('$Package::ArchiveRoot',$v)
 foreach($entry in @(@('ArchiveDb',$source),@('ArchiveJobsDb',$status))) { $manager=New-Object ProbeConnection; $manager.Connection=$entry[1]; $dts.Connections.Add($entry[0],$manager) }
 $results=@()
 if(!$FailuresOnly) {
  Invoke-Step 0
  foreach($job in @($dts.Variables['User::Tables'].Value.Tables[0].Rows)) { [void](Run-Job $job.Id $job.TableName $job.DateColumn) }
  & (Join-Path $PSScriptRoot 'Verify-Export.ps1')
  & (Join-Path $PSScriptRoot 'Verify-JobProcessing.ps1')
  if((Read-Scalar 'SELECT COUNT(*) FROM dbo.Orders;') -ne 2 -or (Read-Scalar 'SELECT COUNT(*) FROM audit.Events;') -ne 1) { throw 'Retention rows not preserved' }
  if((Read-Scalar 'SELECT COUNT(*) FROM dbo.Orders WHERE CreatedAt < DATEADD(day,-1,CONVERT(date,GETDATE()));') -ne 0) { throw 'Eligible orders remain' }
  $results+='PASS: full ScriptMain flow archived and deleted 3508 rows, retained the 3 rows at/after cutoff; composite keys; CSV content verified; continued after invalid job.'
  # A second run must create header-only files, never export the deleted rows again.
  $dts.Variables['$Package::ArchiveRoot'].Value=Join-Path $config.RunDirectory 'csv-retry'
  foreach($job in @($dts.Variables['User::Tables'].Value.Tables[0].Rows | Where-Object Id -ne 2)) {
   $file=Run-Job $job.Id $job.TableName $job.DateColumn
   if(@(Import-Csv -LiteralPath $file -Delimiter ';' -Encoding UTF8).Count) { throw 'Retry re-exported deleted data' }
  }
  $results+='PASS: second run produced 3 header-only CSV files; no previously deleted data was exported again.'
 }
 $command=$source.CreateCommand(); $command.CommandText=@"
CREATE TABLE dbo.WriteFailure(Id int PRIMARY KEY,CreatedAt datetime2 NOT NULL,Payload nvarchar(20));
CREATE TABLE dbo.DeleteFailure(Id int PRIMARY KEY,CreatedAt datetime2 NOT NULL,Payload nvarchar(20));
CREATE TABLE dbo.PreciseKeys(Tenant nvarchar(10) NOT NULL,Stamp datetime2(7) NOT NULL,CreatedAt datetime2 NOT NULL,PRIMARY KEY(Tenant,Stamp));
WITH N AS (SELECT TOP (1001) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
INSERT dbo.WriteFailure SELECT n,DATEADD(day,-3,CONVERT(date,GETDATE())),N'test' FROM N;
INSERT dbo.DeleteFailure SELECT * FROM dbo.WriteFailure;
INSERT dbo.PreciseKeys SELECT N'T',DATEADD(nanosecond,Id*100,CAST('2020-01-01' AS datetime2(7))),CreatedAt FROM dbo.WriteFailure;
INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays,LastSuccesProcessedAt,ErrorMessage)
VALUES(DB_NAME(),N'dbo.WriteFailure',N'CreatedAt',1,'2025-01-01',N'old error'),
(DB_NAME(),N'dbo.DeleteFailure',N'CreatedAt',1,'2025-01-01',N'old error'),
(DB_NAME(),N'dbo.PreciseKeys',N'CreatedAt',1,'2025-01-01',N'old error');
"@; [void]$command.ExecuteNonQuery()
 $command.CommandText="CREATE TRIGGER dbo.RejectArchiveDelete ON dbo.DeleteFailure INSTEAD OF DELETE AS THROW 50002,'Injected delete failure.',1;"; [void]$command.ExecuteNonQuery()
 $dts.Variables['$Package::ArchiveRoot'].Value=Join-Path $config.RunDirectory 'csv-failures'
 foreach($test in @(@('WriteFailure','WriteFailure',0),@('DeleteFailure','Normal',1000),@('PreciseKeys','Normal',1001))) {
  $table='dbo.'+$test[0]; $id=[int](Read-Scalar "SELECT Id FROM Archive.ArchiveJobs WHERE TableName=N'$table';")
  $file=Run-Job $id $table 'CreatedAt' $test[1]
  if($test[0] -eq 'PreciseKeys') {
   if((Read-Scalar "SELECT COUNT(*) FROM $table;") -ne 0 -or @((Import-Csv -LiteralPath $file -Delimiter ';')).Count -ne 1001) { throw 'datetime2 composite key export/deletion mismatch' }
   if((Read-Scalar "SELECT LastProcessedStatus FROM Archive.ArchiveJobs WHERE Id=$id;") -ne 'Success') { throw 'Success status missing' }
   $results+='PASS: 1001 datetime2(7) composite-key records deleted exactly; next job succeeded after write/delete failures.'
  } else {
   if((Read-Scalar "SELECT COUNT(*) FROM $table;") -ne 1001) { throw 'Failure deleted unarchived rows' }
   if((Read-Scalar "SELECT LastProcessedStatus FROM Archive.ArchiveJobs WHERE Id=$id;") -ne 'Error') { throw 'Failure status missing' }
   if((Read-Scalar "SELECT LastSuccesProcessedAt FROM Archive.ArchiveJobs WHERE Id=$id;") -ne [datetime]'2025-01-01') { throw 'Failure overwrote successful date' }
   if($test[0] -eq 'DeleteFailure' -and @((Import-Csv -LiteralPath $file -Delimiter ';')).Count -ne 1000) { throw 'CSV must precede deletion' }
   $results+="PASS: $($test[0]) preserved all 1001 source records and last-success date; status Error; CSV was closed before delete."
  }
 }
 $command=$source.CreateCommand(); $command.CommandText=@"
CREATE TABLE dbo.ExactBatch(Id int PRIMARY KEY,CreatedAt datetime2 NOT NULL,Payload nvarchar(20));
INSERT dbo.ExactBatch SELECT * FROM dbo.WriteFailure;
INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
VALUES(DB_NAME(),N'dbo.ExactBatch',N'CreatedAt',1);
"@; [void]$command.ExecuteNonQuery()
 $id=[int](Read-Scalar "SELECT Id FROM Archive.ArchiveJobs WHERE TableName=N'dbo.ExactBatch';")
 $file=Run-Job $id 'dbo.ExactBatch' 'CreatedAt' 'ExactBatch'
 if((Read-Scalar 'SELECT COUNT(*) FROM dbo.ExactBatch;') -ne 0 -or @(Import-Csv -LiteralPath $file -Delimiter ';').Count -ne 1002) { throw 'Exact-batch test did not drain the table' }
 $results+='PASS: a row added after SELECT/CSV survived deletion of that batch, then was archived and deleted by the following batch; 1002 records exported.'
 $results | Set-Content -LiteralPath (Join-Path $config.RunDirectory 'delete-export-result.txt') -Encoding UTF8
 $results
} finally { $source.Dispose(); $status.Dispose() }
