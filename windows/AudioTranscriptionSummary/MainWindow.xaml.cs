using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using WinRT.Interop;
using AudioTranscriptionSummary.Services;

namespace AudioTranscriptionSummary;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        this.InitializeComponent();
        this.Title = "Audio Transcription Summary";

        // ウィンドウサイズとアイコンを設定
        var hWnd = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(hWnd);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new Windows.Graphics.SizeInt32(1200, 800));

        // アプリアイコンを設定（タイトルバー＋タスクバー）
        try
        {
            var iconPath = AppIconGenerator.GetIconPath();
            appWindow.SetIcon(iconPath);
        }
        catch
        {
            // アイコン生成失敗時は無視（デフォルトアイコンを使用）
        }
    }
}
