$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Script-Source.ps1')
$root=Split-Path $PSScriptRoot -Parent
$package=[xml](Get-Content -Raw (Join-Path $root 'Integration Services Project2/Package.dtsx'))
$ns=New-Object Xml.XmlNamespaceManager($package.NameTable)
$ns.AddNamespace('DTS','www.microsoft.com/SqlServer/Dts')
$guarded=0
foreach($script in $package.SelectNodes('//ScriptProject')) {
    $source=($script.SelectNodes('ProjectItem') | Where-Object { $_.Name -eq 'ScriptMain.cs' }).InnerText
    $access=Get-ScriptVariableAccess $source
    if($script.ReadOnlyVariables -ne $access.Read -or $script.ReadWriteVariables -ne $access.Write) { throw 'Variable access differs from compiled source' }
    if($source -match 'ExecuteJobStep') {
        $guarded++
        if($script.ParentNode.ParentNode.SelectSingleNode('DTS:EventHandlers',$ns)) { throw 'Guarded script still has nested handlers' }
    }
}
if($guarded -ne 9) { throw "Expected nine guarded job scripts, got $guarded" }
# Compile the exact embedded source, using a host substitute that rejects FireError.
$legacy=Get-Content -Raw (Join-Path $PSScriptRoot 'Verify-DeleteExport.ps1')
$stub=[regex]::Match($legacy,'(?s)\$stub=@"\r?\n(.*?)\r?\n"@').Groups[1].Value
$source=$package.SelectSingleNode('//DTS:Executable[@DTS:ObjectName="Initialize daily archive"]/DTS:ObjectData/ScriptProject/ProjectItem[@Name="ScriptMain.cs"]',$ns).InnerText
$source=$source -replace 'namespace ST_[a-f0-9]+','namespace ErrorHandlingProbe'
$reset=$package.SelectSingleNode('//DTS:Executable[@DTS:ObjectName="Initialize job variables"]/DTS:ObjectData/ScriptProject/ProjectItem[@Name="ScriptMain.cs"]',$ns).InnerText
$reset=$reset -replace 'namespace ST_[a-f0-9]+','namespace ResetJobProbe'
$stub=[regex]::Replace($stub,'(?m)^using [^;]+;\r?\n','')
$reset=[regex]::Replace($reset,'(?m)^using [^;]+;\r?\n','')
Add-Type -TypeDefinition ("using System.Data.SqlClient;`n"+$source+"`n"+$reset+"`n"+$stub) -ReferencedAssemblies System.Data,System.Xml,System.Core
$test=New-Object ErrorHandlingProbe.ScriptMain
$test.Dts=New-Object ProbeDts
foreach($match in [regex]::Matches($source,'Dts\.Variables\["([^"]+)"\]')) {
    $key=$match.Groups[1].Value
    if(!$test.Dts.Variables.ContainsKey($key)) { $test.Dts.Variables.Add($key,(New-Object ProbeVariable)) }
}
$destination=Join-Path $root ('verification/error-handling-'+[guid]::NewGuid().ToString('N'))
$values=@{'CurrentDateFrom'=[datetime]'2025-01-01';'ArchiwumPath'=$destination;'DatabaseName'='TestDb';'TableName'='dbo.Orders';'QualifiedTableName'='[TestDb].[dbo].[Orders]';'ColumnDate'='CreatedAt';'KeyColumns'='Id';'JobFailed'=$false;'JobError'=''}
foreach($key in $values.Keys) { $test.Dts.Variables['User::'+$key].Value=$values[$key] }
$test.Main()
if($test.Dts.Variables['User::JobFailed'].Value) { throw 'Clean initialization failed' }
$zip=[string]$test.Dts.Variables['User::ZipFile'].Value
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($zip))
[IO.File]::WriteAllText($zip,'preserve archive')
$test.Main()
if(!$test.Dts.Variables['User::JobFailed'].Value -or $test.Dts.Variables['User::JobError'].Value -notlike '*Archive destination already exists*') { throw 'ZIP collision did not record job failure' }
if($test.Dts.TaskResult -ne 0 -or [IO.File]::ReadAllText($zip) -ne 'preserve archive') { throw 'Collision changed archive or prevented guarded continuation' }
$delete=$package.SelectSingleNode('//DTS:Executable[@DTS:ObjectName="Delete archived day"]/DTS:PropertyExpression[@DTS:Name="Disable"]',$ns)
if(!$delete -or $delete.InnerText -notmatch '@\[User::JobFailed\]') { throw 'Source deletion is not guarded by JobFailed' }
$resetTest=New-Object ResetJobProbe.ScriptMain
$resetTest.Dts=$test.Dts
foreach($match in [regex]::Matches($reset,'Dts\.Variables\["([^"]+)"\]')) {
    $key=$match.Groups[1].Value
    if(!$test.Dts.Variables.ContainsKey($key)) { $test.Dts.Variables.Add($key,(New-Object ProbeVariable)) }
}
$test.Dts.Variables['$Package::ArchiveRoot'].Value=$destination
$resetTest.Main()
if($test.Dts.Variables['User::JobFailed'].Value -or $test.Dts.Variables['User::JobError'].Value -ne '') { throw 'Next job retained previous failure' }
$test.Dts.Variables['User::CurrentDateFrom'].Value=[datetime]'2025-01-02'
$test.Main()
if($test.Dts.Variables['User::JobFailed'].Value) { throw 'Next job initialization failed' }
'PASS: nine guarded scripts; exact variable declarations; no nested Script Task handlers.'
'PASS: embedded initialization handles ZIP collision without raising OnError and preserves archive.'
'PASS: source deletion guarded after failure; next job resets failure and initializes successfully.'
'NOTE: host substitute does not simulate runtime locks; full SSIS execution is still required.'
