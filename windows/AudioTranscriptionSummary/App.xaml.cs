using System;
using System.IO;
using Microsoft.UI.Xaml;

namespace AudioTranscriptionSummary;

public partial class App : Application
{
    private Window? _window;
    private static readonly string LogPath = Path.Combine(
        Path.GetDirectoryName(typeof(App).Assembly.Location) ?? ".", "error.log");

    public App()
    {
        this.InitializeComponent();
        this.UnhandledException += (s, e) =>
        {
            File.AppendAllText(LogPath, $"[Unhandled] {DateTime.Now}: {e.Exception}\n\n");
        };
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception ex)
        {
            File.AppendAllText(LogPath, $"[Launch] {DateTime.Now}: {ex}\n\n");
        }
    }

    public Window? GetWindow() => _window;
}
