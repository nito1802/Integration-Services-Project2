using System.Runtime.InteropServices;
using System.Windows;
using ArchiveRelationsGenerator.Core;

namespace ArchiveRelationsGenerator.Wpf;

public partial class MainWindow : Window
{
    public MainWindow() => InitializeComponent();

    private async void Generate_Click(object sender, RoutedEventArgs e)
    {
        ValidationText.Text = "";
        string input = InputText.Text, database = DatabaseText.Text;
        GenerateButton.IsEnabled = false;
        GenerateButton.Content = "Generowanie…";
        try
        {
            var result = await Task.Run(() => RelationInsertGenerator.Generate(input, database));
            new ResultWindow(result) { Owner = this }.Show();
        }
        catch (FormatException error) { ValidationText.Text = error.Message; }
        catch (Exception error) { ValidationText.Text = "Nie udało się wygenerować SQL: " + error.Message; }
        finally { GenerateButton.IsEnabled = true; GenerateButton.Content = "Generuj INSERT  →"; }
    }
    private void Paste_Click(object sender, RoutedEventArgs e)
    {
        try { InputText.Text = Clipboard.GetText(); ValidationText.Text = ""; InputText.Focus(); }
        catch (ExternalException) { ValidationText.Text = "Schowek jest zajęty. Spróbuj ponownie lub użyj Ctrl+V."; }
    }
    private void Example_Click(object sender, RoutedEventArgs e)
    {
        DatabaseText.Text = "nito_superDb";
        InputText.Text = SampleData.Text;
        ValidationText.Text = "";
    }
}
