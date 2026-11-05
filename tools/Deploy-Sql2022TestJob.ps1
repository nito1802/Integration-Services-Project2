param([string]$Server='.\SSISARCHIVE22')
$ErrorActionPreference='Stop'
if($Server -ne '.\SSISARCHIVE22'){throw 'This helper is restricted to the isolated local test instance.'}
$root=Split-Path $PSScriptRoot -Parent
$runId=Get-Date -Format 'yyyyMMdd_HHmmss'
$database='SsisArchiveTest2022_'+$runId
$archiveRoot='C:\ArchiveTest\Sql2022_'+$runId
$evidence=Join-Path $root 'artifacts/sql2022'
[void](New-Item -ItemType Directory -Path $archiveRoot -Force)
& icacls.exe $archiveRoot /grant 'NT SERVICE\MSSQL$SSISARCHIVE22:(OI)(CI)M' | Out-Null
if($LASTEXITCODE -ne 0){throw 'Cannot grant SQL service access to test archive directory'}
$connectionString="Data Source=$Server;Integrated Security=True;TrustServerCertificate=True"
$connection=New-Object Data.SqlClient.SqlConnection($connectionString)
$connection.Open()
function Execute-Sql([string]$sql) {
 $command=$connection.CreateCommand(); $command.CommandTimeout=180; $command.CommandText=$sql
 try{[void]$command.ExecuteNonQuery()}finally{$command.Dispose()}
}
try {
 $command=$connection.CreateCommand(); $command.CommandText="SELECT CONVERT(int,SERVERPROPERTY('ProductMajorVersion'))"; if($command.ExecuteScalar() -ne 16){throw 'Expected SQL Server 2022'}
 $command.CommandText="SELECT DB_ID(N'SSISDB')"; $catalogId=$command.ExecuteScalar()
 if($catalogId -is [DBNull] -or !$catalogId) {
  Execute-Sql "EXEC sp_configure 'show advanced options',1;RECONFIGURE;EXEC sp_configure 'clr enabled',1;RECONFIGURE;"
  foreach($name in @('Microsoft.SqlServer.Management.Sdk.Sfc','Microsoft.SqlServer.ConnectionInfo','Microsoft.SqlServer.Smo')){[void][Reflection.Assembly]::LoadWithPartialName($name)}
  [void][Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Management.IntegrationServices')
  $integration=New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices($connection)
  $password='Ssis!'+[Guid]::NewGuid().ToString('N')+'9a'
  ConvertTo-SecureString $password -AsPlainText -Force | ConvertFrom-SecureString | Set-Content (Join-Path $evidence 'catalog-key.local.txt')
  $catalog=New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog($integration,'SSISDB',$password)
  $catalog.Create()
 }
 $seed=(Get-Content (Join-Path $root 'docker/ssis-test/Seed.sql') -Raw -Encoding UTF8).Replace('SsisArchiveTest',$database)
 foreach($batch in [regex]::Split($seed,'(?im)^\s*GO\s*$')) {if($batch.Trim()){Execute-Sql $batch}}
 $connection.ChangeDatabase('SSISDB')
 Execute-Sql "IF NOT EXISTS(SELECT 1 FROM catalog.folders WHERE name=N'ArchiveTest') EXEC catalog.create_folder @folder_name=N'ArchiveTest';"
 $command=$connection.CreateCommand(); $command.CommandTimeout=180
 $command.CommandText="EXEC catalog.deploy_project @folder_name=N'ArchiveTest',@project_name=N'Archive.Sql2022',@project_stream=@bytes;"
 $bytes=[IO.File]::ReadAllBytes((Join-Path $evidence 'Archive.Sql2022.ispac'))
 [void]$command.Parameters.Add('@bytes',[Data.SqlDbType]::VarBinary,-1); $command.Parameters['@bytes'].Value=$bytes
 [void]$command.ExecuteNonQuery(); $command.Dispose()
 $testConnection=$connectionString+';Initial Catalog='+$database
 $jobName='SSIS Archive SQL2022 Test '+$runId
 # A real SQL Agent T-SQL step invokes the SSISDB execution synchronously.
 # SQL Agent reports failure if the SSIS catalog execution does not succeed.
 $step=@'
DECLARE @execution bigint;
EXEC SSISDB.catalog.create_execution @folder_name=N'ArchiveTest',@project_name=N'Archive.Sql2022',@package_name=N'Package.dtsx',@use32bitruntime=0,@execution_id=@execution OUTPUT;
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ConnectionString',@parameter_value=N'__CONNECTION__';
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveJobsTable',@parameter_value=N'__DATABASE__.Archive.ArchiveJobs';
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'ArchiveRoot',@parameter_value=N'__ARCHIVE__';
DECLARE @limit int=1000,@logging smallint=1,@synchronous bit=1;
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=30,@parameter_name=N'MaxRecordsPerCsv',@parameter_value=@limit;
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=50,@parameter_name=N'LOGGING_LEVEL',@parameter_value=@logging;
EXEC SSISDB.catalog.set_execution_parameter_value @execution_id=@execution,@object_type=50,@parameter_name=N'SYNCHRONIZED',@parameter_value=@synchronous;
EXEC SSISDB.catalog.start_execution @execution_id=@execution;
IF NOT EXISTS(SELECT 1 FROM SSISDB.catalog.executions WHERE execution_id=@execution AND status=7)
 THROW 51000,'SSIS catalog execution failed. Inspect SSISDB catalog.operation_messages.',1;
'@
 $step=$step.Replace('__CONNECTION__',$testConnection.Replace("'","''")).Replace('__DATABASE__',$database).Replace('__ARCHIVE__',$archiveRoot)
 $connection.ChangeDatabase('msdb')
 $command=$connection.CreateCommand(); $command.CommandTimeout=60
 $command.CommandText=@'
DECLARE @job uniqueidentifier;
EXEC dbo.sp_add_job @job_name=@name,@enabled=1,@description=N'Isolated SQL Server 2022 SSIS archive test. No recurring schedule.',@job_id=@job OUTPUT;
EXEC dbo.sp_add_jobstep @job_id=@job,@step_name=N'Execute SSISDB archive package',@subsystem=N'TSQL',@database_name=N'master',@command=@step,@on_success_action=1,@on_fail_action=2;
EXEC dbo.sp_add_jobserver @job_id=@job;
EXEC dbo.sp_start_job @job_id=@job;
SELECT CONVERT(nvarchar(36),@job);
'@
 [void]$command.Parameters.Add('@name',[Data.SqlDbType]::NVarChar,128); $command.Parameters['@name'].Value=$jobName
 [void]$command.Parameters.Add('@step',[Data.SqlDbType]::NVarChar,-1); $command.Parameters['@step'].Value=$step
 $jobId=[string]$command.ExecuteScalar(); $command.Dispose()
 $config=[ordered]@{Database=$database;ConnectionString=$testConnection;ArchiveJobsTable="$database.Archive.ArchiveJobs";ArchiveRoot=$archiveRoot;MaxRecordsPerCsv=1000;JobName=$jobName;JobId=$jobId}
 $config | ConvertTo-Json | Set-Content (Join-Path $evidence 'test.local.json') -Encoding UTF8
 $step | Set-Content (Join-Path $evidence 'job-step.sql') -Encoding UTF8
 Write-Output "Started SQL Agent job: $jobName"
 Write-Output "Database: $database"
 Write-Output "ArchiveRoot: $archiveRoot"
}finally{$connection.Dispose()}
