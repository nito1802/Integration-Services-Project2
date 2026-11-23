# Shared by package compilation and the isolated verification host.
function Get-ProgressScriptSource([string]$Source,[string]$TaskName,[bool]$HandleJobError) {
    $entry=@'
public void Main()
        {
            const string step = "__STEP__";
            var elapsed = Stopwatch.StartNew();
            __BEFORE__
            Progress("START", step, ProgressContext());
            try { ExecuteLoggedStep(); }
            catch (Exception error)
            {
                Progress("ERROR", step, error.ToString());
                throw;
            }
            finally
            {
                bool failed = Dts.TaskResult == (int)DTSExecResult.Failure __FAILED__;
                Progress(failed ? "FAILED" : "END", step, "elapsedMs=" + elapsed.ElapsedMilliseconds + "; " + ProgressContext() __ERROR__);
                __AFTER__
            }
        }

        private void ExecuteLoggedStep()
'@
    $before=''; $after=''
    if($TaskName -eq 'Initialize job variables') {
        $before='Dts.Variables["User::JobNumber"].Value = Convert.ToInt32(Dts.Variables["User::JobNumber"].Value) + 1; Dts.Variables["User::DayNumber"].Value = 0; Dts.Variables["User::DayRows"].Value = 0L; Dts.Variables["User::DayExportedRows"].Value = 0L; Dts.Variables["User::MemberIndex"].Value = 0;'
        $after='Progress("JOB START", step, "job=" + Dts.Variables["User::JobNumber"].Value + "/" + ((DataSet)Dts.Variables["User::Tables"].Value).Tables[0].Rows.Count + "; " + ProgressContext());'
        $before='Dts.Variables["User::JobStartedTicks"].Value = Stopwatch.GetTimestamp(); ' + $before
        $after+=' Summary("JOB START", Convert.ToString(Dts.Variables["User::TableName"].Value), "job=" + Dts.Variables["User::JobNumber"].Value + "/" + ((DataSet)Dts.Variables["User::Tables"].Value).Tables[0].Rows.Count + "; database=" + Dts.Variables["User::DatabaseName"].Value);'
    }
    if($TaskName -eq 'Prepare related archive group') { $before='Dts.Variables["User::DayNumber"].Value = Convert.ToInt32(Dts.Variables["User::DayNumber"].Value) + 1;' }
    if($TaskName -eq 'Prepare archive member') { $before='Dts.Variables["User::DayRows"].Value = 0L; Dts.Variables["User::DayExportedRows"].Value = 0L;' }
    if($TaskName -eq 'Plan archive graph') { $after='Progress("PLAN", step, "tables=" + ((DataSet)Dts.Variables["User::ArchiveMembers"].Value).Tables[0].Rows.Count + "; " + ProgressContext());' }
    if($TaskName -eq 'Log job result') { $after='Progress("JOB END", step, "status=" + (Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value) ? "Error" : "Success") + "; " + ProgressContext());' }
    if($TaskName -eq 'Check overall archive result') { $after='Progress(Convert.ToInt32(Dts.Variables["User::FailedJobs"].Value) > 0 ? "RUN ERROR" : "RUN SUCCESS", "Package", "jobs=" + Dts.Variables["User::JobNumber"].Value + "; failedJobs=" + Dts.Variables["User::FailedJobs"].Value);' }
    if($TaskName -eq 'Prepare archive member') {
        $before='Dts.Variables["User::MemberStartedTicks"].Value = Stopwatch.GetTimestamp(); ' + $before
        $after+=' Summary("TABLE START", Convert.ToString(Dts.Variables["User::TableName"].Value), "phase=export+zip; " + ProgressContext());'
    }
    if($TaskName -eq 'Collect ZIP process diagnostics') {
        $after+=' if (Convert.ToInt64(Dts.Variables["User::MemberStartedTicks"].Value) > 0) { Summary("TABLE END", Convert.ToString(Dts.Variables["User::TableName"].Value), "phase=export+zip; status=" + (Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value) ? "Error" : "Success") + "; " + SummaryElapsed(Convert.ToInt64(Dts.Variables["User::MemberStartedTicks"].Value)) + "; " + ProgressContext()); Dts.Variables["User::MemberStartedTicks"].Value = 0L; }'
    }
    if($TaskName -eq 'Log job result') {
        $after+=' Summary("JOB END", Convert.ToString(Dts.Variables["User::TableName"].Value), "status=" + (Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value) ? "Error" : "Success") + "; database=" + Dts.Variables["User::DatabaseName"].Value + "; days=" + Dts.Variables["User::DayNumber"].Value + "; " + SummaryElapsed(Convert.ToInt64(Dts.Variables["User::JobStartedTicks"].Value)));'
    }
    if($TaskName -eq 'Check overall archive result') {
        $after+=' Summary("RUN END", "Package", "status=" + (Convert.ToInt32(Dts.Variables["User::FailedJobs"].Value) > 0 ? "Error" : "Success") + "; jobs=" + Dts.Variables["User::JobNumber"].Value + "; failedJobs=" + Dts.Variables["User::FailedJobs"].Value + "; " + SummaryElapsed(Convert.ToInt64(Dts.Variables["User::RunStartedTicks"].Value)));'
    }
    $entry=$entry.Replace('__STEP__',$TaskName).Replace('__BEFORE__',$before).Replace('__AFTER__',$after)
    $entry=$entry.Replace('__FAILED__',$(if($HandleJobError){' || Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value)'}else{''}))
    $entry=$entry.Replace('__ERROR__',$(if($HandleJobError){' + (failed ? "; error=" + Dts.Variables["User::JobError"].Value : "")'}else{''}))
    return $Source.Replace('public void Main()',$entry)
}

function Get-JobScriptSource([string]$Source) {
    if($Source -notmatch 'public void Main\(\)') { throw 'Script entry point not found' }
    $entry=@'
public void Main()
        {
            try { ExecuteJobStep(); }
            catch (Exception error)
            {
                Dts.Variables["User::JobFailed"].Value = true;
                Dts.Variables["User::JobError"].Value = error.ToString();
                // Continue only through the JobFailed guards to Save job result.
                // Do not fire OnError while this Script Task owns variable locks.
                Dts.TaskResult = (int)DTSExecResult.Success;
            }
        }

        private void ExecuteJobStep()
'@
    return $Source.Replace('public void Main()', $entry)
}

function Get-ScriptVariableAccess([string]$Source) {
    $access=@([regex]::Matches($Source,'Dts\.Variables\["([^"]+)"\]\.Value\s*(=(?!=))?'))
    $writes=@($access | Where-Object { $_.Groups[2].Success } | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $reads=@($access | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin $writes } | Select-Object -Unique)
    return @{ Read=($reads -join ','); Write=($writes -join ',') }
}
