using IntegrationServicesProject2.Console.GenericSignature;
using IntegrationServicesProject2.Database;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Process = IntegrationServicesProject2.Console.GenericSignature.Process;

namespace IntegrationServicesProject2.Console;

public sealed class TestDataSeeder
{
    public Task SeedAsync(CancellationToken cancellationToken = default) => SeedCoreAsync(false, cancellationToken);

    public Task LittleSeedAsync(CancellationToken cancellationToken = default) => SeedCoreAsync(true, cancellationToken);

    private async Task SeedCoreAsync(bool little, CancellationToken cancellationToken)
    {
        foreach (var database in new[] { "nito_superDb", "nito_SomeApps" })
        {
            var builder = new SqlConnectionStringBuilder(DatabaseConfiguration.GetConnectionString()) { InitialCatalog = database };
            var options = new DbContextOptionsBuilder<GenericSignatureDbContext>().UseSqlServer(builder.ConnectionString,
                sql => sql.CommandTimeout(300).MaxBatchSize(200)).Options;
            await using var db = new GenericSignatureDbContext(options);
            await db.Database.OpenConnectionAsync(cancellationToken);
            await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            // Serialize complete reseeds, including DDL and archive configuration changes.
            await db.Database.ExecuteSqlRawAsync("""
                DECLARE @r int;
                EXEC @r=sys.sp_getapplock @Resource=N'GenericSignatureTest.Seed',@LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=10000;
                IF @r<0 THROW 50010,'Could not acquire seed lock.',1;
                """, cancellationToken);
            System.Console.WriteLine($"{database}: przygotowanie konfiguracji i usunięcie ArchiveScenarioTest...");
            await ExecuteAsync(db, await ReadScriptAsync("CreateArchiveJobRelations.sql", cancellationToken), "nito_superDb", cancellationToken);
            await db.Database.ExecuteSqlRawAsync("""
                DECLARE @sql nvarchar(max)=N'';
                SELECT @sql+=N'ALTER TABLE '+QUOTENAME(s.name)+N'.'+QUOTENAME(t.name)+N' DROP CONSTRAINT '+QUOTENAME(f.name)+N';'
                FROM sys.foreign_keys f JOIN sys.tables t ON t.object_id=f.parent_object_id
                JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name=N'ArchiveScenarioTest';
                EXEC sys.sp_executesql @sql;
                SET @sql=N'';
                SELECT @sql+=N'DROP TABLE '+QUOTENAME(s.name)+N'.'+QUOTENAME(t.name)+N';'
                FROM sys.tables t JOIN sys.schemas s ON s.schema_id=t.schema_id WHERE s.name=N'ArchiveScenarioTest';
                EXEC sys.sp_executesql @sql;
                IF SCHEMA_ID(N'ArchiveScenarioTest') IS NOT NULL EXEC(N'DROP SCHEMA ArchiveScenarioTest');
                """, cancellationToken);
            System.Console.WriteLine($"{database}: tworzenie modelu EF...");
            await using (var check = db.Database.GetDbConnection().CreateCommand())
            {
                check.Transaction = transaction.GetDbTransaction();
                check.CommandText = "SELECT COUNT(*) FROM sys.tables WHERE schema_id=SCHEMA_ID(N'GenericSignatureTest');";
                if (Convert.ToInt32(await check.ExecuteScalarAsync(cancellationToken)) == 0)
                    foreach (var batch in System.Text.RegularExpressions.Regex.Split(db.Database.GenerateCreateScript(), @"^GO\s*$", System.Text.RegularExpressions.RegexOptions.Multiline | System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                        if (!string.IsNullOrWhiteSpace(batch)) await db.Database.ExecuteSqlRawAsync(batch, cancellationToken);
            }
            await db.Database.ExecuteSqlRawAsync("""
                IF OBJECT_ID(N'GenericSignatureTest.ExportLoadTest',N'U') IS NULL
                BEGIN
                    CREATE TABLE GenericSignatureTest.ExportLoadTest
                        (Id bigint NOT NULL PRIMARY KEY,CreatedAt datetime2(7) NOT NULL,Payload nvarchar(128) NOT NULL);
                    CREATE INDEX IX_ExportLoadTest_CreatedAt ON GenericSignatureTest.ExportLoadTest(CreatedAt);
                END;
                DELETE FROM GenericSignatureTest.ExportLoadTest;
                ALTER TABLE GenericSignatureTest.ExportLoadTest ALTER COLUMN Payload nvarchar(128) NOT NULL;
                DELETE FROM GenericSignatureTest.AutentiRecipients;
                DELETE FROM GenericSignatureTest.EkdProcessHistories;
                DELETE FROM GenericSignatureTest.AutentiProcesses;
                DELETE FROM GenericSignatureTest.EkdProcesses;
                DELETE FROM GenericSignatureTest.CallProcesses;
                DELETE FROM GenericSignatureTest.ProcessData;
                DELETE FROM GenericSignatureTest.Processes;
                DELETE FROM GenericSignatureTest.ProcessTypes;
                DELETE FROM GenericSignatureTest.EkdStatuses;
                DBCC CHECKIDENT ('GenericSignatureTest.EkdProcessHistories',RESEED,0) WITH NO_INFOMSGS;
                """, cancellationToken);
            System.Console.WriteLine($"{database}: generowanie {(little ? "małego zestawu z lat 2023 i 2024 (po sześć dni)" : "danych od 2023 roku")}...");
            db.AddRange(new NewProcessType { Id="CUSTOMER_ONBOARDING", Name="Test onboarding" },
                new NewProcessType { Id="ACCOUNT_CREATE", Name="Test account" });
            db.AddRange(new EkdStatus { Id="CREATED", Name="Created" }, new EkdStatus { Id="SIGNED", Name="Signed" });
            await db.SaveChangesAsync(cancellationToken);
            db.ChangeTracker.Clear();
            var today = DateTime.Today;
            var start = new DateTime(2023,1,1);
            var dates = little
                ? new[] { 2023, 2024 }.SelectMany(year => new[] {
                    new DateTime(year,1,3), new DateTime(year,1,5),
                    new DateTime(year,3,7), new DateTime(year,3,9),
                    new DateTime(year,6,12), new DateTime(year,6,14) }).ToArray()
                : Enumerable.Range(0,(today-start).Days+1).Select(offset => start.AddDays(offset)).ToArray();
            var processes = 0;
            var populatedDays = 0;

            for (var dayIndex=0; dayIndex<dates.Length; dayIndex++)
            {
                var day=dates[dayIndex];
                var offset=(day-start).Days;
                // About 95% of days populated, with small days and occasional larger bursts.
                var count=little ? 3+(dayIndex%6)%4 : offset%23==7 ? 0 : offset%31==0 ? 35 : 1+(offset*17%9);
                if(count>0) populatedDays++;
                for(var n=0; n<count; n++)
                {
                    var created=day.AddMinutes(30+(n*37)%1400);
                    var p=new Process { Id=Guid.NewGuid(), ProcessTypeId=n%2==0?"CUSTOMER_ONBOARDING":"ACCOUNT_CREATE",
                        SignatureTypeId=n%2==0?"AUTENTI":"EKD", Ai2Key=$"T{offset:D5}{n:D3}", EqNumber=$"TEST-{offset}-{n}",
                        Status=n%3==0?"Started":"Success", CreationDate=created, SignatureTypeSelectionDate=n%4==0?null:created.AddMinutes(1),
                        AvailableSignatureTypes="AUTENTI,EKD,CALL", UserLogin="seed.user", ClientWorkingMode="TEST", ExternalId=$"seed-{offset}-{n}" };
                    for(var a=0;a<(n+offset)%3;a++)
                    {
                        var envelope=new AutentiProcess { EnvelopeId=Guid.NewGuid().ToString(), AutentiEnvelopeStatus=(AutentiEnvelopeStatus)((n+a)%4),
                            DocumentId=Guid.NewGuid(), DocumentTitle=$"Dokument testowy {offset}/{n}/{a}", DocuwareName="Test document", DocuwareFile="test.pdf",
                            DocuwareDescription="Synthetic data", DocuwareIndexesJson="{\"test\":true}", DocuwareId=n, IsActive=n%2==0,
                            ExpirationDate=n%3==0?null:created.AddDays(30) };
                        for(var r=0;r<1+(n+a)%4;r++) envelope.AutentiRecipients.Add(new AutentiRecipient { RecipientId=Guid.NewGuid(),
                            Email=$"recipient{r}@example.invalid", Status=(AutentiRecipientStatus)((n+r)%4), Ai2Key=p.Ai2Key });
                        p.AutentiProcesses.Add(envelope);
                    }
                    for(var e=0;e<(n+offset+1)%3;e++)
                    {
                        var ekd=new EkdProcess { Id=Guid.NewGuid(), ExternalId=n%3==0?null:Guid.NewGuid(), CreationDate=created,
                            UserLogin="seed.user", UserName="Test User", CustomerNumber=$"{n:D6}", CustomerName="Test Customer",
                            CustomerEmail="customer@example.invalid", CustomerPesel=null, CustomerId=Guid.NewGuid(), CustomerAi2Key=p.Ai2Key!,
                            StatusId=n%2==0?"CREATED":"SIGNED", SentDate=n%3==0?null:created.AddMinutes(2), DocuwareId=n,
                            DocuwareFile="test.pdf", CompanyNumber="TEST01", UploadDocumentUrl="https://example.invalid/test.pdf",
                            AcceptanceChannel="TEST", DecisionDate=n%3==0?null:created.AddMinutes(5), IsNewGenericSignature=true,
                            DocumentId=Guid.NewGuid(), IsActive=n%2==0, ExpirationDate=created.AddDays(30) };
                        for(var h=0;h<1+(n+e)%4;h++) ekd.ProcessHistories.Add(new EkdProcessHistory { Date=created.AddMinutes(h),
                            StatusId=h==0?"CREATED":"SIGNED", UserLogin="seed.user", UserName="Test User" });
                        p.EkdProcesses.Add(ekd);
                    }
                    if(n%2==0) p.CallProcesses.Add(new CallProcess { Id=Guid.NewGuid(), DocumentId=Guid.NewGuid(), DocumentTitle="Test call document", DocuwareFile="call.pdf" });
                    for(var d=0;d<1+n%4;d++) p.ProcessData.Add(new ProcessData { Id=Guid.NewGuid(), Ai2Key=p.Ai2Key,
                        DataType=$"TEST_{d}", Data=$"{{\"date\":\"{created:O}\",\"text\":\"Zażółć gęślą, test \\\"CSV\\\"\",\"value\":{n}}}" });
                    db.Processes.Add(p);
                    processes++;
                }
                if(dayIndex%30==29 || dayIndex==dates.Length-1)
                {
                    await db.SaveChangesAsync(cancellationToken);
                    db.ChangeTracker.Clear();
                    System.Console.WriteLine($"{database}: zapisano do {day:yyyy-MM-dd}, {processes} procesów...");
                }
            }
            System.Console.WriteLine($"{database}: seed ExportLoadTest — 100 000 rekordów, około 10 MB CSV...");
            await db.Database.ExecuteSqlRawAsync("""
                ;WITH n AS (SELECT TOP (100000) CONVERT(bigint,ROW_NUMBER() OVER(ORDER BY (SELECT NULL))) AS Id
                    FROM sys.all_objects a CROSS JOIN sys.all_objects b)
                INSERT GenericSignatureTest.ExportLoadTest(Id,CreatedAt,Payload)
                SELECT Id,DATEADD(second,CONVERT(int,Id%86400),CONVERT(datetime2(7),'20240614')),
                    REPLICATE(CONVERT(nvarchar(max),N'0123456789ABCDEF'),4) FROM n;
                IF @@ROWCOUNT<>100000 THROW 50014,'Load fixture must contain 100000 records.',1;
                """, cancellationToken);
            await ExecuteAsync(db, """
                DELETE FROM Archive.ArchiveJobRelations WHERE DatabaseName=@DatabaseName
                  AND (LEFT(ParentTable,20)=N'ArchiveScenarioTest.' OR LEFT(ChildTable,20)=N'ArchiveScenarioTest.'
                    OR LEFT(ParentTable,21)=N'GenericSignatureTest.' OR LEFT(ChildTable,21)=N'GenericSignatureTest.');
                DELETE FROM Archive.ArchiveJobs WHERE DatabaseName=@DatabaseName AND LEFT(TableName,20)=N'ArchiveScenarioTest.';
                IF NOT EXISTS(SELECT 1 FROM Archive.ArchiveJobs WHERE DatabaseName=@DatabaseName AND TableName=N'GenericSignatureTest.Processes')
                    INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
                    VALUES(@DatabaseName,N'GenericSignatureTest.Processes',N'CreationDate',30);
                UPDATE Archive.ArchiveJobs SET DateColumn=N'CreationDate',ArchiveOlderThanDays=30,
                    LastSuccesProcessedAt=NULL,LastProcessedAt=NULL,LastProcessedStatus=NULL,ErrorMessage=NULL
                WHERE DatabaseName=@DatabaseName AND TableName=N'GenericSignatureTest.Processes';
                IF NOT EXISTS(SELECT 1 FROM Archive.ArchiveJobs WHERE DatabaseName=@DatabaseName AND TableName=N'GenericSignatureTest.ExportLoadTest')
                    INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
                    VALUES(@DatabaseName,N'GenericSignatureTest.ExportLoadTest',N'CreatedAt',30);
                UPDATE Archive.ArchiveJobs SET DateColumn=N'CreatedAt',ArchiveOlderThanDays=30,
                    LastSuccesProcessedAt=NULL,LastProcessedAt=NULL,LastProcessedStatus=NULL,ErrorMessage=NULL
                WHERE DatabaseName=@DatabaseName AND TableName=N'GenericSignatureTest.ExportLoadTest';
                INSERT Archive.ArchiveJobRelations(DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
                SELECT @DatabaseName,N'GenericSignatureTest.'+p,N'GenericSignatureTest.'+c,pk,ck FROM (VALUES
                    (N'Processes',N'AutentiProcesses',N'Id',N'ProcessId'),
                    (N'Processes',N'CallProcesses',N'Id',N'ProcessId'),
                    (N'Processes',N'EkdProcesses',N'Id',N'ProcessId'),
                    (N'Processes',N'ProcessData',N'Id',N'ProcessId'),
                    (N'AutentiProcesses',N'AutentiRecipients',N'EnvelopeId',N'EnvelopeId'),
                    (N'EkdProcesses',N'EkdProcessHistories',N'Id',N'ProcessId')
                ) e(p,c,pk,ck);
                """, "nito_superDb", cancellationToken, database);
            await transaction.CommitAsync(cancellationToken);
            System.Console.WriteLine($"{database}: {processes} procesów; {populatedDays} dni z danymi ({dates[0]:yyyy-MM-dd}–{dates[^1]:yyyy-MM-dd}); ExportLoadTest: 100 000 rekordów; 2 joby, 6 relacji.");
        }
    }

    private static async Task ExecuteAsync(GenericSignatureDbContext db, string sql, string catalog,
        CancellationToken ct, string? databaseName=null)
    {
        // Use the same retained SQL session and transaction for cross-database configuration.
        await using var command=db.Database.GetDbConnection().CreateCommand();
        command.Transaction=db.Database.CurrentTransaction!.GetDbTransaction();
        command.CommandTimeout=300;
        command.CommandText=$"USE [{catalog}];\n"+sql+$"\nUSE [{db.Database.GetDbConnection().Database}];";
        if(databaseName!=null) command.Parameters.Add(new SqlParameter("@DatabaseName",databaseName));
        await command.ExecuteNonQueryAsync(ct);
    }
    private static async Task<string> ReadScriptAsync(string name,CancellationToken ct)
    {
        using var stream=typeof(TestDataSeeder).Assembly.GetManifestResourceStream($"IntegrationServicesProject2.Console.{name}")
            ?? throw new InvalidOperationException($"Brak skryptu {name}.");
        using var reader=new StreamReader(stream);
        var script=await reader.ReadToEndAsync(ct);
        // The source file also contains manually runnable examples and diagnostic queries.
        const string migrationEnd="END CATCH;";
        var end=script.IndexOf(migrationEnd,StringComparison.OrdinalIgnoreCase);
        if(end<0) throw new InvalidOperationException("Brak końca migracji relacji.");
        return script[..(end+migrationEnd.Length)];
    }
}
