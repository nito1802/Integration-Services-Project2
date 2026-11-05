param([string]$ConfigPath,[string]$ReportPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(!$ConfigPath){$ConfigPath=Join-Path $root 'docker/ssis-test/ssis.local.json'}
if(!$ReportPath){$ReportPath=Join-Path $root 'verification/docker-archive-results.txt'}
$config=Get-Content $ConfigPath -Raw | ConvertFrom-Json
$db=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
try {
 $db.Open(); $cmd=$db.CreateCommand()
 $cmd.CommandText='SELECT Id,TableName,LastProcessedStatus,ErrorMessage,LastProcessedAt,LastSuccesProcessedAt FROM Archive.ArchiveJobs ORDER BY Id'
 $table=New-Object Data.DataTable; $adapter=New-Object Data.SqlClient.SqlDataAdapter($cmd); [void]$adapter.Fill($table)
 if($table.Rows.Count -ne 3) { throw 'Expected three test jobs' }
 foreach($job in $table.Rows) {
  if($job.LastProcessedStatus -ne 'Success' -or $job.ErrorMessage -isnot [DBNull] -or $job.LastProcessedAt -ne $job.LastSuccesProcessedAt) { throw "Job not successful: $($job.TableName) $($job.LastProcessedStatus) $($job.ErrorMessage)" }
 }
 $cmd.CommandText='SELECT (SELECT COUNT(*) FROM Demo.Orders),(SELECT COUNT(*) FROM Demo.Events),(SELECT COUNT(*) FROM Demo.EmptyTable),(SELECT COUNT(*) FROM Demo.Orders WHERE CreatedAt < DATEADD(day,-30,CONVERT(date,GETDATE()))),(SELECT COUNT(*) FROM Demo.Events WHERE HappenedAt < DATEADD(day,-30,CONVERT(date,GETDATE())))'
 $reader=$cmd.ExecuteReader()
 try { [void]$reader.Read(); $counts=0..4 | ForEach-Object { $reader.GetInt32($_) } } finally { $reader.Dispose() }
 if(($counts -join ',') -ne '2,1,0,0,0') { throw "Wrong remaining counts: $counts" }
} finally { $db.Dispose() }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$database=if($config.Database){$config.Database}else{'SsisArchiveTest'}
$archiveDirectory=Join-Path $config.ArchiveRoot $database
$zips=@(Get-ChildItem $archiveDirectory -Filter '*.zip' -Recurse)
if($zips.Count -ne 5) { throw "Expected 5 ZIPs, found $($zips.Count)" }
$totals=@{ 'Demo.Orders'=0; 'Demo.Events'=0 }
$keys=@{ 'Demo.Orders'=(New-Object 'System.Collections.Generic.HashSet[int]'); 'Demo.Events'=(New-Object 'System.Collections.Generic.HashSet[int]') }
$csvCount=0
foreach($zip in $zips) {
 & 'C:\Program Files\7-Zip\7z.exe' t -tzip $zip.FullName | Out-Null
 if($LASTEXITCODE -ne 0) { throw "Invalid ZIP: $($zip.FullName)" }
 $tableName=$zip.Directory.Parent.Parent.Name
 $archive=[IO.Compression.ZipFile]::OpenRead($zip.FullName)
 try {
  $expectedSizes=if($tableName -eq 'Demo.Orders') { '1000,1000,500' } else { '1000,1' }
  $sizes=@()
  foreach($entry in @($archive.Entries | Sort-Object Name)) {
   if($entry.FullName -ne $entry.Name -or $entry.Name -notmatch ('^'+$zip.BaseName+'_part[1-9][0-9]*\.csv$')) { throw 'Invalid CSV name' }
   $stream=$entry.Open(); $memory=New-Object IO.MemoryStream
   try { $stream.CopyTo($memory); $bytes=$memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
   if($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw 'UTF8 BOM missing' }
   $content=[Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)
   $rows=@($content | ConvertFrom-Csv -Delimiter ';'); $sizes+=$rows.Count; $csvCount++
   foreach($row in $rows) {
    if($tableName -eq 'Demo.Orders') {
     $id=[int]$row.'Id (int)'; $date=[datetime]($row.PSObject.Properties | Where-Object Name -like 'CreatedAt (*').Value
     if([decimal]($row.PSObject.Properties | Where-Object Name -like 'Amount (*').Value -ne $id*[decimal]1.2345) { throw 'Amount mismatch' }
     $expectedNote=if($id%7 -eq 0) { '' } else { "Zażółć; `"cytat`"`r`ndruga linia" }
     if(($row.PSObject.Properties | Where-Object Name -like 'Note (*').Value -cne $expectedNote) { throw 'Note mismatch' }
    } else {
     $id=[int]$row.'SequenceNo (int)'; $date=[datetime]($row.PSObject.Properties | Where-Object Name -like 'HappenedAt (*').Value
     if(($row.PSObject.Properties | Where-Object Name -like 'Kind (*').Value -ne 'Sensor' -or ($row.PSObject.Properties | Where-Object Name -like 'Details (*').Value -ne 'event') { throw 'Event mismatch' }
    }
    if(!$keys[$tableName].Add($id)) { throw 'Duplicate key in archives' }
    if($date.ToString('yyyy_MM_dd') -ne $zip.BaseName) { throw 'Mixed archive dates' }
   }
   $totals[$tableName]+=$rows.Count
  }
  if(($sizes -join ',') -ne $expectedSizes) { throw "Wrong CSV sizes: $sizes" }
 } finally { $archive.Dispose() }
}
if($totals['Demo.Orders'] -ne 7500 -or $totals['Demo.Events'] -ne 2002 -or $csvCount -ne 13) { throw 'Wrong export totals' }
foreach($name in @('Demo.Orders','Demo.Events')) { for($id=1;$id -le $totals[$name];$id++) { if(!$keys[$name].Contains($id)) { throw "Missing $name key $id" } } }
if(@(Get-ChildItem $archiveDirectory -Filter '*.csv' -Recurse).Count -ne 0) { throw 'Temporary CSVs left behind' }
$report=@('PASS: all 3 jobs Success; ErrorMessage NULL; success timestamps match.', 'PASS: ZIP integrity, UTF8 BOM, CSV names, day grouping, unique keys, field values, multiline text, NULLs and 1000-row limit.', 'ZIPs: 5; CSVs inside ZIPs: 13; archived Orders: 7500; archived Events: 2002.', 'Remaining Orders: 2; Events: 1; EmptyTable: 0; eligible source rows: 0.', 'Temporary CSV files: 0.', ('ArchiveRoot: '+$config.ArchiveRoot))
$report | Set-Content $ReportPath -Encoding UTF8
$report
