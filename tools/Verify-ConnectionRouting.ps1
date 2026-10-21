$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification/latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated fixture' }
[void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ManagedDTS')
$app=New-Object Microsoft.SqlServer.Dts.Runtime.Application
$package=$app.LoadPackage((Join-Path $PSScriptRoot 'compatibility-test.dtsx'),$null)
$package.Parameters['ConnectionString'].Value=$config.ConnectionString
foreach($connection in $package.Connections) { $connection.ConnectionString=$config.ConnectionString }
$hostTask=$package.Executables['For each archive job'].Executables['Read column definitions']
$sessionId=$null
foreach($database in @('master','tempdb',$config.Database,'master')) {
    $literal=$database.Replace("'","''"); $identifier='['+$database.Replace(']',']]')+']'
    $package.Variables['User::ShapeSql'].Value="SELECT N'$literal' AS DatabaseName,(SELECT COUNT(*) FROM $identifier.sys.tables) AS TableCount,@@SPID AS SessionId;"
    $result=$hostTask.Execute($package.Connections,$hostTask.Variables,$null,$null,$null)
    $row=$package.Variables['User::ShapeData'].Value.Tables[0].Rows[0]
    if($result -ne 'Success' -or $row.DatabaseName -ne $database) { throw "Qualified database query failed for $database" }
    if($null -ne $sessionId -and $sessionId -ne $row.SessionId) { throw 'Retained source session changed' }
    $sessionId=$row.SessionId
    Write-Output "PASS: qualified database $database; retained session $sessionId"
}
