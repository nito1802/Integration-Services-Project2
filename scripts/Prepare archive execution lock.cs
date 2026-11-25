        public void Main()
        {
            string root = Path.GetFullPath(Convert.ToString(Dts.Variables["$Package::ArchiveRoot"].Value))
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).ToUpperInvariant();
            string resource;
            using (var hash = System.Security.Cryptography.SHA256.Create())
                resource = "CSVArchive:" + BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(root))).Replace("-", "");
            Dts.Variables["User::ArchiveLockSql"].Value =
                "DECLARE @r int; EXEC @r=master.sys.sp_getapplock @Resource=N'" + resource +
                "',@LockMode=N'Exclusive',@LockOwner=N'Session',@LockTimeout=0; " +
                "IF @r<0 THROW 50021,'Another archive run is using this ArchiveRoot. Stop or finish it before retrying.',1; SELECT CAST(1 AS bit);";
            Dts.Variables["User::ArchiveUnlockSql"].Value =
                "DECLARE @r int; EXEC @r=master.sys.sp_releaseapplock @Resource=N'" + resource +
                "',@LockOwner=N'Session'; IF @r<0 THROW 50022,'Could not release archive execution lock.',1; SELECT CAST(0 AS bit);";
            Dts.TaskResult = (int)DTSExecResult.Success;
        }
