using IntegrationServicesProject2.Console;
using IntegrationServicesProject2.Database;
using IntegrationServicesProject2.Database.Consts;
using IntegrationServicesProject2.Database.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

Console.OutputEncoding = System.Text.Encoding.UTF8;

try
{
    //if (args.Length == 1 && args[0].Equals("seed-fk-tables", StringComparison.OrdinalIgnoreCase))
    //{
    //    await new ForeignKeyTestDataCreator().SeedAsync();
    //    return 0;
    //}

    //if (args.Length == 1 && args[0].Equals("seed-events", StringComparison.OrdinalIgnoreCase))
    //{
    //    await new EventTestDataCreator().AddAsync();
    //    return 0;
    //}

    await new ForeignKeyTestDataCreator().SeedAsync();

    await new EventTestDataCreator().AddAsync();

    if (args.Length > 0)
    {
        Console.Error.WriteLine("Użycie: bez argumentów (dodanie zadań) lub seed-events (50000 zdarzeń testowych).");
        return 1;
    }

    var services = new ServiceCollection();
    services.AddDbContext<ArchiveJobsDbContext>(options =>
        options.UseSqlServer(DatabaseConfiguration.GetConnectionString(),
            sql => sql.MigrationsHistoryTable("__EFMigrationsHistory", DatabaseEnvironment.DatabaseSchema)));
    services.AddScoped<ArchiveJobCreator>();

    await using var provider = services.BuildServiceProvider(validateScopes: true);
    await using var scope = provider.CreateAsyncScope();
    var jobs = new List<ArchiveJob>
    {
        new()
        {
            DatabaseName = "nito_superDb",
            TableName = "MyData.cccc",
            DateColumn = "CreatedAt",
            ArchiveOlderThanDays = 90
        },
        new()
        {
            DatabaseName = "nito_superDb",
            TableName = "SmartHome.xxx",
            DateColumn = "CreatedAt",
            ArchiveOlderThanDays = 30
        }
    };

    await scope.ServiceProvider.GetRequiredService<ArchiveJobCreator>().AddAsync(jobs);
    Console.WriteLine($"Dodano {jobs.Count} zadań do Archive.ArchiveJobs.");
    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Nie udało się uruchomić aplikacji: {exception.Message}");
    return 1;
}