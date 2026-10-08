$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt')) -Raw | ConvertFrom-Json
$files=@(Get-ChildItem -LiteralPath $config.ArchiveRoot -Recurse -Filter '*.csv')
if($files.Count -ne 7) { throw "Expected 7 CSV files; got $($files.Count)" }
$orders=@(); $events=@(); $sizes=@()
foreach($file in $files) {
 $bytes=[IO.File]::ReadAllBytes($file.FullName)
 if($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw "Missing UTF-8 BOM: $file" }
 $rows=@(Import-Csv -LiteralPath $file.FullName -Delimiter ';' -Encoding UTF8)
 if($rows.Count -gt 1000 -or $rows.Count -eq 0) { throw "Invalid batch size: $file" }
 $sizes+=$rows.Count
 if($file.Directory.Parent.Name -eq 'table_dbo~002EOrders') { $orders+=$rows } else { $events+=$rows }
}
if($orders.Count -ne 2506 -or $events.Count -ne 1002) { throw 'Table row counts differ' }
$ids=@($orders | ForEach-Object { [long]$_.'OrderNo (bigint)' } | Sort-Object)
$expected=@(1..2505)+3000
if(@(Compare-Object $expected $ids).Count) { throw 'Missing, duplicated, or out-of-range order IDs' }
$eventKeys=@($events | ForEach-Object { $_.'Kind (nvarchar)'+'|'+$_.'SequenceNo (int)' })
if(@($eventKeys | Sort-Object -Unique).Count -ne 1002) { throw 'Duplicate event composite keys' }
foreach($row in $events) {
 $id=[int]$row.'SequenceNo (int)'
 $kind=if($id -eq 2000 -or $id%2 -eq 0) {'A'} else {'B'}
 if(($id -lt 1 -or ($id -gt 1001 -and $id -ne 2000)) -or $row.'Kind (nvarchar)' -ne $kind) { throw 'Unexpected event key' }
}
$first=$orders | Where-Object { $_.'OrderNo (bigint)' -eq '1' }
if($first.'Note (nvarchar)' -cne "semi; `"quote`"`r`nZażółć gęślą jaźń") { throw 'CSV escaping, multiline, or Unicode mismatch' }
if($first.'Amount (decimal)' -ne '1.2345') { throw 'Invariant decimal format mismatch' }
$nullRow=$orders | Where-Object { $_.'OrderNo (bigint)' -eq '7' }
if($nullRow.'Note (nvarchar)' -ne '') { throw 'NULL format mismatch' }
if(@(Get-ChildItem -LiteralPath $config.ArchiveRoot -Recurse -Filter '*.tmp').Count) { throw 'Unfinished export files' }
if(@(Get-ChildItem -LiteralPath $config.ArchiveRoot -Recurse -Filter '_SUCCESS.txt').Count -ne 4) { throw 'Missing day markers' }
$result="PASS: 7 CSV; Orders=2506; Events=1002; total=3508; batches=$($sizes -join ','); exact keys; cutoff; Unicode; quotes; semicolons; multiline; NULL; decimal; BOM; 4 completed days."
$result | Set-Content -LiteralPath (Join-Path $config.RunDirectory 'verification-result.txt') -Encoding UTF8
$result
