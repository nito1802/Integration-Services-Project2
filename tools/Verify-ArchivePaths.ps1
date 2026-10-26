$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$main=[IO.File]::ReadAllText((Join-Path $root 'scripts/Initialize daily archive.cs'))
# Run the actual script body with an in-memory SSIS variable collection; no SQL is executed.
$harness=@'
using System;
using System.IO;
using System.Text;
using System.Globalization;
using System.Collections.Generic;
public enum DTSExecResult { Success }
public class PathTestVariable { public object Value; }
public class PathTestContext {
    public Dictionary<string,PathTestVariable> Variables = new Dictionary<string,PathTestVariable>();
    public int TaskResult;
}
public class ArchivePathTest {
    public PathTestContext Dts = new PathTestContext();
    public void Set(string name, object value) { Dts.Variables[name]=new PathTestVariable { Value=value }; }
    public string Get(string name) { return Convert.ToString(Dts.Variables[name].Value); }
    // __MAIN__
}
'@
Add-Type -TypeDefinition ($harness.Replace('// __MAIN__',$main))
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
        if(!(Test-Path -LiteralPath $expected -PathType Container)) { throw 'Missing working directory' }
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
