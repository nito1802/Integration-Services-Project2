param([switch]$RetrySucceeded)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content -LiteralPath (Get-Content -LiteralPath (Join-Path $root 'verification\latest-config.txt')) -Raw | ConvertFrom-Json
if($config.Database -notmatch '^CodexArchiveFlow_[a-f0-9]{32}$') { throw 'Expected isolated LocalDB test' }
$connection=New-Object Data.SqlClient.SqlConnection($config.ConnectionString)
try {
    $connection.Open()
    $command=$connection.CreateCommand()
    $command.CommandText='SELECT * FROM Archive.ArchiveJobs ORDER BY Id; SELECT * FROM Archive.ProcessingAudit ORDER BY AuditId;'
    $adapter=New-Object Data.SqlClient.SqlDataAdapter($command)
    $data=New-Object Data.DataSet
    [void]$adapter.Fill($data)
    if($data.Tables[0].Rows.Count -ne 4) { throw 'Expected all four jobs, including failing job' }
    foreach($job in $data.Tables[0].Rows) {
        if($job.Id -eq 2 -and !$RetrySucceeded) {
            if($job.LastProcessedStatus -ne 'Error' -or $job.ErrorMessage -notlike '*MissingDateColumn*') { throw 'Missing persisted error' }
            if($job.LastSuccesProcessedAt -ne [datetime]'2025-01-01') { throw 'Failure changed last success timestamp' }
            if($job.LastProcessedAt -le $job.LastSuccesProcessedAt) { throw 'Failure attempt timestamp not updated' }
        } else {
            if($job.LastProcessedStatus -ne 'Success' -or $job.ErrorMessage -isnot [DBNull]) { throw ('Expected success and no error for job '+$job.Id) }
            if($job.LastProcessedAt -ne $job.LastSuccesProcessedAt) { throw 'Success timestamps must be identical' }
        }
        $starts=@($data.Tables[1].Rows | Where-Object { $_.JobId -eq $job.Id -and $_.Status -is [DBNull] -and $_.ErrorMessage -is [DBNull] })
        $expectedStarts=if($RetrySucceeded){2}else{1}
        if($starts.Count -ne $expectedStarts) { throw ('Start did not clear error/status for job '+$job.Id) }
    }
    $data.Tables[0] | Select-Object Id,TableName,LastProcessedStatus,LastProcessedAt,LastSuccesProcessedAt | Format-Table -AutoSize
    $command.CommandText='SELECT COUNT(*) FROM sys.dm_tran_session_transactions st JOIN sys.dm_tran_database_transactions dt ON st.transaction_id=dt.transaction_id WHERE dt.database_id=DB_ID();'
    if([int]$command.ExecuteScalar() -ne 0) { throw 'Transaction was left open after processing' }
    $message=if($RetrySucceeded){'PASS: retry cleared ErrorMessage; all 4 jobs Success; success dates identical; both starts cleared errors; no open source transactions.'}else{'PASS: 3 Success, 1 Error; failure retained prior success date; processing continued after error; start cleared old errors; no open source transactions.'}
    $message | Set-Content -LiteralPath (Join-Path $config.RunDirectory ('job-state-'+[bool]$RetrySucceeded+'.txt')) -Encoding UTF8
    $message
} finally { $connection.Dispose() }
