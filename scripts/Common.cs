using System;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Text;
using System.Globalization;
using System.Diagnostics;
using System.Collections.Generic;
using Microsoft.SqlServer.Dts.Runtime;

namespace __NAMESPACE__
{
    [Microsoft.SqlServer.Dts.Tasks.ScriptTask.SSISScriptTaskEntryPointAttribute]
    public partial class ScriptMain : Microsoft.SqlServer.Dts.Tasks.ScriptTask.VSTARTScriptObjectModelBase
    {
        private void Run(Action work)
        {
            if (Convert.ToBoolean(Dts.Variables["User::JobActive"].Value) && Convert.ToBoolean(Dts.Variables["User::JobFailed"].Value))
            {
                Dts.TaskResult = (int)DTSExecResult.Success;
                return;
            }
            try { work(); Dts.TaskResult = (int)DTSExecResult.Success; }
            catch (Exception ex)
            {
                if (!Convert.ToBoolean(Dts.Variables["User::JobActive"].Value))
                {
                    Dts.Events.FireError(0, "CSV Archive", ex.ToString(), "", 0);
                    Dts.TaskResult = (int)DTSExecResult.Failure;
                    return;
                }
                Dts.Variables["User::JobFailed"].Value = true;
                Dts.Variables["User::JobError"].Value = ex.ToString();
                Dts.Events.FireWarning(0, "CSV Archive", "Job=" + Dts.Variables["User::ArchiveJobId"].Value + "; table=" + Convert.ToString(Dts.Variables["User::TableName"].Value, CultureInfo.InvariantCulture) + "; " + ex, "", 0);
                // Skip the remaining export; SetTableStatus persists this result afterwards.
                Dts.TaskResult = (int)DTSExecResult.Success;
            }
        }
        // __MAIN__
    }
}
