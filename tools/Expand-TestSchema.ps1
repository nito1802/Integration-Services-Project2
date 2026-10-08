$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected an isolated test database' }
Get-ChildItem -LiteralPath $config.ArchiveRoot -Recurse -Filter '*.csv' | Get-FileHash -Algorithm SHA256 | Select-Object Path,Hash | Export-Csv -LiteralPath (Join-Path $config.RunDirectory 'first-export-hashes.csv') -NoTypeInformation
$connection=New-Object Data.SqlClient.SqlConnection(('Data Source=(localdb)\MSSQLLocalDB;Integrated Security=True;Initial Catalog='+$config.Database))
try {
 $connection.Open()
 $command=$connection.CreateCommand()
 $command.CommandText="ALTER TABLE dbo.Orders ADD Extra nvarchar(50) NOT NULL CONSTRAINT DF_Orders_Extra DEFAULT N'new column' WITH VALUES;"
 [void]$command.ExecuteNonQuery()
} finally { $connection.Dispose() }
'Added a column in the isolated test database only.'
