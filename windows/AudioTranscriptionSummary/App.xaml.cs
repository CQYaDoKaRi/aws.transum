using System;
using System.IO;
using Microsoft.UI.Xaml;

namespace AudioTranscriptionSummary;

public partial class App : Application
{
    private Window? _window;
    private static System.Threading.Mutex? _mutex;
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
        // 二重起動防止
        _mutex = new System.Threading.Mutex(true, "AudioTranscriptionSummary_SingleInstance", out bool createdNew);
        if (!createdNew)
        {
            // 既に起動中 → 終了
            Environment.Exit(0);
            return;
        }

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
