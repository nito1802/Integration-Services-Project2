$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$main=[IO.File]::ReadAllText((Join-Path $root 'scripts/Initialize daily archive.cs'))
# Run the actual script body with an in-memory SSIS variable collection; no SQL is executed.
$harness=@'
using System;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
public enum DTSExecResult { Success }
public class PathTestVariable { public object Value; }
public class PathTestContext {
    public Dictionary<string,PathTestVariable> Variables = new Dictionary<string,PathTestVariable>();
    public int TaskResult; public PathTestEvents Events = new PathTestEvents();
}
public class PathTestEvents { public void FireInformation(int a, string b, string c, string d, int e, ref bool f) {} }
public class ArchivePathTest {
    public PathTestContext Dts = new PathTestContext();
    public void Set(string name, object value) { Dts.Variables[name]=new PathTestVariable { Value=value }; }
    public string Get(string name) { return Convert.ToString(Dts.Variables[name].Value); }
    // __MAIN__
}
'@
$writer=[IO.File]::ReadAllText((Join-Path $root 'scripts/Write batch to CSV.cs')).Replace('public void Main()', 'public void Write()')
Add-Type -TypeDefinition ($harness.Replace('// __MAIN__',$main+$writer)) -ReferencedAssemblies System.Data,System.Xml,System.Core
$destination=Join-Path $root ('verification/archive-paths-'+[guid]::NewGuid().ToString('N'))
$months=@('styczen','luty','marzec','kwiecien','maj','czerwiec','lipiec','sierpien','wrzesien','pazdziernik','listopad','grudzien')
function New-ArchiveTest($database,$month) {
    $test=New-Object ArchivePathTest
    foreach($name in @('FolderFullPath','OutputFile','CurrentDateTo','BatchNumber','BatchHasRows','DayHasFiles','ZipFile','ZipArguments','ZipTestArguments','DayRows','DayExportedRows','StageDaySql','DeleteSql')) { $test.Set('User::'+$name,$null) }
    $test.Set('User::CurrentDateFrom',[datetime]::new(2025,$month,1))
    $test.Set('User::ArchiwumPath',$destination)
    $test.Set('User::DatabaseName',$database)
    $test.Set('User::TableName','dbo.SameTable')
    $test.Set('User::QualifiedTableName','['+$database+'].[dbo].[SameTable]')
    $test.Set('User::ColumnDate','CreatedAt')
    $test.Set('User::KeyColumns','Id')
    return $test
}
foreach($month in 1..12) {
    foreach($database in @('DatabaseA','DatabaseB')) {
        $test=New-ArchiveTest $database $month
        $test.Main()
        $day=([datetime]::new(2025,$month,1)).ToString('yyyy_MM_dd')
        $expected=Join-Path $destination "$database/dbo.SameTable/2025/$($months[$month-1])/$day"
        if($test.Get('User::FolderFullPath') -ne $expected) { throw 'Unexpected archive path' }
        if($test.Get('User::ZipFile') -ne $expected+'.zip') { throw 'Unexpected ZIP path' }
        if(Test-Path -LiteralPath $expected) { throw 'Initialization created a directory for an empty day' }
        [void][IO.Directory]::CreateDirectory($expected)
        $rejected=$false
        try { $test.Main() } catch { if($_.Exception.ToString() -notlike '*destination already exists*') { throw }; $rejected=$true }
        if(!$rejected) { throw 'Existing directory was not protected' }
        # Empty working directory is ours; replace it with a ZIP sentinel to test ZIP protection.
        [IO.Directory]::Delete($expected)
        [IO.File]::WriteAllText($expected+'.zip','preserve existing ZIP')
        $rejected=$false
        try { $test.Main() } catch { if($_.Exception.ToString() -notlike '*destination already exists*') { throw }; $rejected=$true }
        if(!$rejected -or [IO.File]::ReadAllText($expected+'.zip') -ne 'preserve existing ZIP') { throw 'Existing ZIP was not protected' }
    }
}
$escaped=New-ArchiveTest 'Database:~A' 10
$escaped.Main()
if($escaped.Get('User::ZipFile') -notlike '*Database~003A~007EA*') { throw 'Database path encoding failed' }
Write-Output 'PASS: 12 ASCII month names, two databases with the same table, database path encoding, folder and ZIP collision protection.'
Write-Output ('Test artifacts: '+$destination)

$destination=Join-Path $destination 'sparse'
foreach($year in 2024,2025) {
    foreach($month in 1..12) {
        $test=New-ArchiveTest 'SparseDb' $month
        $test.Set('User::CurrentDateFrom',[datetime]::new($year,$month,1))
        $test.Main()
        $data=New-Object Data.DataTable
        [void]$data.Columns.Add('Id',[int])
        $schema=New-Object Data.DataTable
        [void]$schema.Columns.Add('ColumnName',[string])
        [void]$schema.Columns.Add('DataType',[type])
        [void]$schema.Rows.Add('Id',[int])
        if($year -eq 2025 -and $month -in 1,2) { [void]$data.Rows.Add(1) }
        $dataset=New-Object Data.DataSet
        [void]$dataset.Tables.Add($data)
        $test.Set('User::BatchData',$dataset)
        $test.Set('User::TableSchema',$schema)
        $test.Set('User::CsvHeader','Id')
        $test.Set('User::CutoffDate',[datetime]'2026-01-01')
        $test.Write()
        $folder=$test.Get('User::FolderFullPath')
        if($data.Rows.Count -eq 0 -and (Test-Path -LiteralPath $folder)) { throw 'Empty day created a directory' }
        if($data.Rows.Count -gt 0) {
            $csv=$test.Get('User::OutputFile')
            if(!(Test-Path -LiteralPath $csv)) { throw 'CSV missing' }
            Compress-Archive -LiteralPath $csv -DestinationPath $test.Get('User::ZipFile')
            [IO.File]::Delete($csv)
            [IO.Directory]::Delete($folder)
        }
    }
}
$tablePath=Join-Path $destination 'SparseDb/dbo.SameTable'
if(Test-Path -LiteralPath (Join-Path $tablePath '2024')) { throw 'Empty year exists' }
$actualMonths=@(Get-ChildItem -LiteralPath (Join-Path $tablePath '2025') -Directory | Select-Object -ExpandProperty Name | Sort-Object)
if(($actualMonths -join ',') -ne 'luty,styczen') { throw 'Unexpected month directories' }
Write-Output 'PASS: actual CSV writer, 24 months; empty year absent; only January and February with ZIPs.'
