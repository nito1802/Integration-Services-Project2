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
$package.Variables['User::ShapeSql'].Value='SELECT DB_NAME() AS DatabaseName;'
foreach($database in @('master','tempdb',$config.Database,'master')) {
    $package.Variables['User::DatabaseName'].Value=$database
    $result=$hostTask.Execute($package.Connections,$hostTask.Variables,$null,$null,$null)
    if($result -ne 'Success' -or $package.Variables['User::ShapeData'].Value.Tables[0].Rows[0]['DatabaseName'] -ne $database) { throw "Database routing failed for $database; result=$result; observed=$($package.Variables['User::ShapeData'].Value.Tables[0].Rows[0]['DatabaseName']); errors=$(@($package.Errors | ForEach-Object Description) -join '; ')" }
    Write-Output "PASS: Execute SQL Task connection manager selects $database"
}
