using IntegrationServicesProject2.Console;

Console.OutputEncoding = System.Text.Encoding.UTF8;
try
{
    await new TestDataSeeder().LittleSeedAsync();
    //await new TestDataSeeder().SeedAsync();

    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Seed nie powiódł się: {exception.GetBaseException().Message}");
    if (exception.GetBaseException() is Microsoft.Data.SqlClient.SqlException sql)
        foreach (Microsoft.Data.SqlClient.SqlError error in sql.Errors) Console.Error.WriteLine($"SQL {error.Number}, linia {error.LineNumber}, procedura {error.Procedure}");
    return 1;
}