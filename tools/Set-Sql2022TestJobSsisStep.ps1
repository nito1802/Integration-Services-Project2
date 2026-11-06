$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'artifacts/sql2022'
$config=Get-Content (Join-Path $directory 'test.local.json') -Raw | ConvertFrom-Json
$connection=New-Object Data.SqlClient.SqlConnection('Data Source=.\SSISARCHIVE22;Integrated Security=True;Initial Catalog=msdb;TrustServerCertificate=True')
$step=@'
/ISSERVER "\"\SSISDB\ArchiveTest\Archive.Sql2022\Package.dtsx\"" /SERVER "\".\SSISARCHIVE22\"" /Par "\"$Package::ConnectionString\"";"\"__CONNECTION__\"" /Par "\"$Package::ArchiveJobsTable\"";"\"__TABLE__\"" /Par "\"$Package::ArchiveRoot\"";"\"__ROOT__\"" /Par "\"$Package::MaxRecordsPerCsv(Int32)\"";__LIMIT__ /Par "\"$ServerOption::LOGGING_LEVEL(Int16)\"";1 /Par "\"$ServerOption::SYNCHRONIZED(Boolean)\"";True /CALLERINFO SQLAGENT /REPORTING E
'@
foreach($value in @($config.ConnectionString,$config.ArchiveJobsTable,$config.ArchiveRoot)){if($value.Contains('"')){throw 'Unexpected quote in test parameter'}}
$step=$step.Replace('__CONNECTION__',$config.ConnectionString).Replace('__TABLE__',$config.ArchiveJobsTable).Replace('__ROOT__',$config.ArchiveRoot).Replace('__LIMIT__',[string][int]$config.MaxRecordsPerCsv)
try {
 $connection.Open(); $command=$connection.CreateCommand()
 $command.CommandText='SELECT j.name,s.step_id,s.step_name,s.subsystem,s.command FROM dbo.sysjobs j JOIN dbo.sysjobsteps s ON j.job_id=s.job_id WHERE j.job_id=@job;'
 [void]$command.Parameters.Add('@job',[Data.SqlDbType]::UniqueIdentifier); $command.Parameters['@job'].Value=[guid]$config.JobId
 $table=New-Object Data.DataTable; $adapter=New-Object Data.SqlClient.SqlDataAdapter($command); [void]$adapter.Fill($table)
 if($table.Rows.Count -ne 1 -or $table.Rows[0].name -ne $config.JobName){throw 'Expected the configured single-step test job'}
 $old=$table.Rows[0]
 if($old.subsystem -eq 'TSQL') {
  [ordered]@{JobId=$config.JobId;StepId=$old.step_id;StepName=$old.step_name;Subsystem=$old.subsystem;Command=$old.command} | ConvertTo-Json | Set-Content (Join-Path $directory 'job-step-before-ssis.local.json') -Encoding UTF8
 }
 $command.CommandText="EXEC dbo.sp_update_jobstep @job_id=@job,@step_id=1,@step_name=N'Execute SSISDB archive package',@subsystem=N'SSIS',@command=@step,@database_name=NULL,@on_success_action=1,@on_fail_action=2;"
 [void]$command.Parameters.Add('@step',[Data.SqlDbType]::NVarChar,-1); $command.Parameters['@step'].Value=$step
 [void]$command.ExecuteNonQuery()
 $step | Set-Content (Join-Path $directory 'job-step-ssis.txt') -Encoding UTF8
 Write-Output ('Updated existing job step to SSIS: '+$config.JobName)
}finally{$connection.Dispose()}
