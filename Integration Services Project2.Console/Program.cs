using IntegrationServicesProject2.Console;

Console.OutputEncoding = System.Text.Encoding.UTF8;
try
{
    await new TestDataSeeder().SeedAsync();
    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Seed nie powiódł się: {exception.Message}");
    return 1;
}