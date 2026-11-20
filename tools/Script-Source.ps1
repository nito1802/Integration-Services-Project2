# Shared by package compilation and the isolated verification host.
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
