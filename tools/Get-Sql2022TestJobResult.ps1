$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$directory=Join-Path $root 'artifacts/sql2022'
$config=Get-Content (Join-Path $directory 'test.local.json') -Raw | ConvertFrom-Json
$connection=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
try {
 $connection.Open(); $command=$connection.CreateCommand()
 $command.CommandText=@'
SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) Version,CAST(SERVERPROPERTY('Edition') AS nvarchar(128)) Edition;
SELECT j.name,h.step_id,h.run_status,h.run_date,h.run_time,h.run_duration,h.message FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobhistory h ON j.job_id=h.job_id WHERE j.job_id=@job ORDER BY h.instance_id;
SELECT TOP(1) execution_id,folder_name,project_name,package_name,status,start_time,end_time FROM SSISDB.catalog.executions WHERE project_name=N'Archive.Sql2022' ORDER BY execution_id DESC;
SELECT message_type,message FROM SSISDB.catalog.operation_messages WHERE operation_id=(SELECT MAX(execution_id) FROM SSISDB.catalog.executions WHERE project_name=N'Archive.Sql2022') AND message_type IN (110,120,130);
SELECT Id,TableName,LastProcessedStatus,ErrorMessage,LastProcessedAt,LastSuccesProcessedAt FROM Archive.ArchiveJobs ORDER BY Id;
'@
 [void]$command.Parameters.Add('@job',[Data.SqlDbType]::UniqueIdentifier); $command.Parameters['@job'].Value=[guid]$config.JobId
 $data=New-Object Data.DataSet; $adapter=New-Object Data.SqlClient.SqlDataAdapter($command); [void]$adapter.Fill($data)
 $jobResult=@($data.Tables[1].Rows | Where-Object step_id -eq 0 | Select-Object -Last 1)
 if($jobResult.Count -ne 1 -or $jobResult[0].run_status -ne 1){throw 'SQL Agent job did not succeed'}
 if($data.Tables[2].Rows.Count -ne 1 -or $data.Tables[2].Rows[0].status -ne 7){throw 'SSIS catalog execution did not succeed'}
 if($data.Tables[3].Rows.Count){$data.Tables[3] | Format-List | Out-String | Write-Output;throw 'Warnings/errors were reported by SSISDB'}
 $report=@('PASS: real SQL Server Agent job succeeded; SSISDB execution status=7; no SSIS warnings/errors.',('ArchiveRoot: '+$config.ArchiveRoot),('ISPAC SHA256: '+(Get-FileHash (Join-Path $directory 'Archive.Sql2022.ispac') -Algorithm SHA256).Hash))
 foreach($table in $data.Tables){$report+=($table | Format-Table -Wrap | Out-String -Width 220)}
 $report | Set-Content (Join-Path $directory 'job-result.txt') -Encoding UTF8
 $report
}finally{$connection.Dispose()}
