using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using System;

namespace ArchiveRelationsGenerator.Wpf;

public partial class ResultWindow : Window
{
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(3) };
    public ResultWindow(GenerationResult result)
    {
        InitializeComponent();
        SqlText.Text = result.Sql;
        ResultInfo.Text = $"Relacje: {result.RelationCount} · Pominięte duplikaty: {result.DuplicateCount}. Tekst można zaznaczać i kopiować. Wykonaj go samodzielnie w bazie konfiguracji Archive.";
        timer.Tick += (_, _) => { Snackbar.Visibility = Visibility.Collapsed; timer.Stop(); };
        Closed += (_, _) => timer.Stop();
    }
    private void SelectAll_Click(object sender, RoutedEventArgs e) { SqlText.Focus(); SqlText.SelectAll(); }
    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(SqlText.Text); ShowSnack("Skopiowano SQL do schowka"); }
        catch (ExternalException) { ShowSnack("Schowek jest zajęty — spróbuj ponownie"); }
    }
    private void ShowSnack(string text)
    {
        timer.Stop(); SnackText.Text = text; Snackbar.Visibility = Visibility.Visible; timer.Start();
    }
}
