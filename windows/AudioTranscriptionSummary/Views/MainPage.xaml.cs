#nullable enable
using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using AudioTranscriptionSummary.ViewModels;
using AudioTranscriptionSummary.Services;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Views;

public sealed partial class MainPage : Page
{
    private readonly MainViewModel _vm;

    public MainPage()
    {
        this.InitializeComponent();
        _vm = new MainViewModel();
        this.Loaded += MainPage_Loaded;
    }

    private void MainPage_Loaded(object sender, RoutedEventArgs e)
    {
        // Populate language ComboBoxes
        var languages = Enum.GetValues<TranslationLanguage>();
        foreach (var lang in languages)
        {
            RealtimeTranslateLang.Items.Add(lang.ToDisplayName());
            TranscriptTranslateLang.Items.Add(lang.ToDisplayName());
            SummaryTranslateLang.Items.Add(lang.ToDisplayName());
        }
        RealtimeTranslateLang.SelectedIndex = 0;
        TranscriptTranslateLang.SelectedIndex = 0;
        SummaryTranslateLang.SelectedIndex = 0;

        // Sync ComboBox selection to ViewModels
        RealtimeTranslateLang.SelectionChanged += (_, _) =>
        {
            if (RealtimeTranslateLang.SelectedIndex >= 0)
                _vm.RealtimeTranslationVM.SelectedTargetLanguage = languages[RealtimeTranslateLang.SelectedIndex];
        };
        TranscriptTranslateLang.SelectionChanged += (_, _) =>
        {
            if (TranscriptTranslateLang.SelectedIndex >= 0)
                _vm.TranscriptTranslationVM.SelectedTargetLanguage = languages[TranscriptTranslateLang.SelectedIndex];
        };
        SummaryTranslateLang.SelectionChanged += (_, _) =>
        {
            if (SummaryTranslateLang.SelectedIndex >= 0)
                _vm.SummaryTranslationVM.SelectedTargetLanguage = languages[SummaryTranslateLang.SelectedIndex];
        };

        // Bind audio sources
        AudioSourcePicker.ItemsSource = _vm.AudioSources;
        // Select System Audio by default
        var loopbackIdx = _vm.AudioSources.FindIndex(s => s.IsLoopback);
        AudioSourcePicker.SelectedIndex = loopbackIdx >= 0 ? loopbackIdx : 0;

        AudioSourcePicker.SelectionChanged += (_, _) =>
        {
            if (AudioSourcePicker.SelectedItem is AudioSourceInfo src)
                _vm.SelectedSource = src;
        };

        // Task 7.1: Hide realtime section when disabled
        var settings = new SettingsStore().Load();
        RealtimeSection.Visibility = settings.IsRealtimeEnabled
            ? Visibility.Visible : Visibility.Collapsed;

        // Wire MainViewModel property changes
        _vm.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(MainViewModel.AudioLevel):
                    LevelMeter.Value = _vm.AudioLevel;
                    break;
                case nameof(MainViewModel.IsCapturing):
                    UpdateRecordingUI();
                    break;
                case nameof(MainViewModel.Transcript):
                    TranscriptText.Text = _vm.Transcript?.Text ?? "";
                    break;
                case nameof(MainViewModel.Summary):
                    SummaryText.Text = _vm.Summary?.Text ?? "";
                    break;
                case nameof(MainViewModel.TranscriptionProgress):
                    TranscriptionProgressBar.Value = _vm.TranscriptionProgress;
                    TranscriptionProgressBar.Visibility = _vm.TranscriptionProgress > 0 && _vm.TranscriptionProgress < 100
                        ? Visibility.Visible : Visibility.Collapsed;
                    break;
                case nameof(MainViewModel.ErrorMessage):
                    if (_vm.ErrorMessage != null)
                        ShowErrorDialog(_vm.ErrorMessage);
                    break;
                case nameof(MainViewModel.AudioFile):
                    UpdateFileInfo();
                    break;
                case nameof(MainViewModel.IsPlaying):
                    PlayPauseButton.Content = _vm.IsPlaying ? "\uE769" : "\uE768";
                    break;
                case nameof(MainViewModel.PlaybackPosition):
                    UpdateTimeDisplay();
                    break;
                case nameof(MainViewModel.AppCpuDisplay):
                    AppCpuText.Text = _vm.AppCpuDisplay;
                    break;
                case nameof(MainViewModel.SystemCpuDisplay):
                    SystemCpuText.Text = _vm.SystemCpuDisplay;
                    break;
                case nameof(MainViewModel.MemoryDisplay):
                    MemoryText.Text = _vm.MemoryDisplay;
                    break;
            }
        };

        // Wire RealtimeTranscriptionVM property changes
        _vm.RealtimeTranscriptionVM.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(RealtimeTranscriptionViewModel.FinalText):
                    RealtimeFinalRun.Text = _vm.RealtimeTranscriptionVM.FinalText;
                    ScrollRealtimeToBottom();
                    break;
                case nameof(RealtimeTranscriptionViewModel.PartialText):
                    RealtimePartialRun.Text = _vm.RealtimeTranscriptionVM.PartialText;
                    ScrollRealtimeToBottom();
                    break;
                case nameof(RealtimeTranscriptionViewModel.DetectedLanguage):
                    var lang = _vm.RealtimeTranscriptionVM.DetectedLanguage;
                    if (!string.IsNullOrEmpty(lang))
                    {
                        LanguageBadgeText.Text = lang;
                        LanguageBadge.Visibility = Visibility.Visible;
                    }
                    else
                    {
                        LanguageBadge.Visibility = Visibility.Collapsed;
                    }
                    break;
                case nameof(RealtimeTranscriptionViewModel.ErrorMessage):
                    RealtimeErrorText.Text = _vm.RealtimeTranscriptionVM.ErrorMessage ?? "";
                    break;
            }
        };

        // Wire TranslationVM property changes
        _vm.RealtimeTranslationVM.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(TranslationViewModel.TranslatedText):
                    RealtimeTranslationText.Text = _vm.RealtimeTranslationVM.TranslatedText;
                    break;
                case nameof(TranslationViewModel.IsTranslating):
                    RealtimeTranslateProgress.IsActive = _vm.RealtimeTranslationVM.IsTranslating;
                    break;
            }
        };

        _vm.TranscriptTranslationVM.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(TranslationViewModel.TranslatedText):
                    TranscriptTranslationText.Text = _vm.TranscriptTranslationVM.TranslatedText;
                    break;
                case nameof(TranslationViewModel.IsTranslating):
                    TranscriptTranslateProgress.IsActive = _vm.TranscriptTranslationVM.IsTranslating;
                    break;
            }
        };

        _vm.SummaryTranslationVM.PropertyChanged += (_, args) =>
        {
            switch (args.PropertyName)
            {
                case nameof(TranslationViewModel.TranslatedText):
                    SummaryTranslationText.Text = _vm.SummaryTranslationVM.TranslatedText;
                    break;
                case nameof(TranslationViewModel.IsTranslating):
                    SummaryTranslateProgress.IsActive = _vm.SummaryTranslationVM.IsTranslating;
                    break;
            }
        };
    }

    private void ScrollRealtimeToBottom()
    {
        RealtimeScrollViewer.ChangeView(null, RealtimeScrollViewer.ScrollableHeight, null);
    }

    private void UpdateRecordingUI()
    {
        RecordButton.Visibility = _vm.IsCapturing ? Visibility.Collapsed : Visibility.Visible;
        StopRecordButton.Visibility = _vm.IsCapturing ? Visibility.Visible : Visibility.Collapsed;
        CancelButton.Visibility = _vm.IsCapturing ? Visibility.Visible : Visibility.Collapsed;

        if (_vm.IsCapturing)
        {
            // 録音開始: 入力とリアルタイムを展開、音声文字起こしと要約を閉じる
            InputSection.IsExpanded = true;
            RealtimeSection.IsExpanded = true;
            TranscriptSection.IsExpanded = false;
            SummarySection.IsExpanded = false;
        }
        else
        {
            // 録音終了: 音声文字起こしと要約を展開
            TranscriptSection.IsExpanded = true;
            SummarySection.IsExpanded = true;
        }
    }

    private void UpdateFileInfo()
    {
        if (_vm.AudioFile != null)
        {
            var af = _vm.AudioFile;
            FileInfoText.Text = $"{af.FileName} ({af.Extension}) - {af.Duration:mm\\:ss}";
            PlayerPanel.Visibility = Visibility.Visible;
            PositionSlider.Maximum = _vm.AudioDuration.TotalSeconds;
        }
        else
        {
            FileInfoText.Text = "";
            PlayerPanel.Visibility = Visibility.Collapsed;
        }
    }

    private void UpdateTimeDisplay()
    {
        var cur = _vm.PlaybackPosition;
        var dur = _vm.AudioDuration;
        TimeText.Text = $"{cur:mm\\:ss} / {dur:mm\\:ss}";
        if (!_isSliderDragging)
            PositionSlider.Value = cur.TotalSeconds;
    }

    // Record / Stop / Cancel
    private async void OnRecordClick(object sender, RoutedEventArgs e) => await _vm.StartCaptureCommand.ExecuteAsync(null);
    private void OnStopRecordClick(object sender, RoutedEventArgs e) => _vm.StopCaptureCommand.Execute(null);
    private void OnCancelClick(object sender, RoutedEventArgs e) => _vm.CancelCaptureCommand.Execute(null);

    // Export
    private async void OnExportClick(object sender, RoutedEventArgs e)
    {
        if (_vm.Transcript == null) return;

        var settings = new SettingsStore().Load();
        if (string.IsNullOrEmpty(settings.ExportDirectoryPath))
        {
            var picker = new FolderPicker();
            picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
            picker.FileTypeFilter.Add("*");

            var hwnd = GetWindowHandle();
            if (hwnd != IntPtr.Zero)
                WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

            var folder = await picker.PickSingleFolderAsync();
            if (folder != null)
            {
                try
                {
                    var exportMgr = new ExportManager();
                    exportMgr.Export(_vm.Transcript, _vm.Summary, folder.Path);
                }
                catch (AppError ex)
                {
                    _vm.ErrorMessage = ex.Message;
                }
            }
        }
        else
        {
            _vm.ExportCommand.Execute(null);
        }
    }

    // Transcribe
    private void OnTranscribeClick(object sender, RoutedEventArgs e)
        => _vm.TranscribeAndSummarizeCommand.Execute(null);

    // Play/Pause
    private void OnPlayPause(object sender, RoutedEventArgs e)
        => _vm.TogglePlaybackCommand.Execute(null);

    // Slider
    private bool _isSliderDragging;
    private void OnPositionSliderChanged(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs e)
    {
        if (Math.Abs(e.NewValue - _vm.PlaybackPosition.TotalSeconds) > 0.5)
        {
            _vm.SeekCommand.Execute(e.NewValue);
        }
    }

    // Settings dialog
    private async void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        var store = new SettingsStore();
        var settings = store.Load();

        var accessKeyBox = new TextBox { Header = "Access Key ID", Text = settings.AccessKeyId, Margin = new Thickness(0, 0, 0, 8) };
        var secretKeyBox = new PasswordBox { Header = "Secret Access Key", Password = settings.SecretAccessKey, Margin = new Thickness(0, 0, 0, 8) };

        var regionCombo = new ComboBox { Header = "リージョン", Margin = new Thickness(0, 0, 0, 8), HorizontalAlignment = HorizontalAlignment.Stretch };
        var regions = new[] { "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
            "us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1", "eu-west-2", "eu-central-1", "ca-central-1" };
        foreach (var r in regions) regionCombo.Items.Add(r);
        regionCombo.SelectedItem = settings.Region;

        var s3Bucket = new TextBox { Header = "S3 バケット名", Text = settings.S3BucketName, Margin = new Thickness(0, 0, 0, 8) };

        var recordDirBox = new TextBox { Header = "録音保存先", Text = settings.RecordingDirectoryPath, IsReadOnly = true, HorizontalAlignment = HorizontalAlignment.Stretch };
        var recordDirBtn = new Button { Content = "📁 フォルダを選択...", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 8) };
        recordDirBtn.Click += async (_, _) =>
        {
            var fp = new FolderPicker();
            fp.FileTypeFilter.Add("*");
            var hwnd = GetWindowHandle();
            if (hwnd != IntPtr.Zero) WinRT.Interop.InitializeWithWindow.Initialize(fp, hwnd);
            var f = await fp.PickSingleFolderAsync();
            if (f != null) recordDirBox.Text = f.Path;
        };

        var exportDirBox = new TextBox { Header = "エクスポート保存先", Text = settings.ExportDirectoryPath, IsReadOnly = true, HorizontalAlignment = HorizontalAlignment.Stretch };
        var exportDirBtn = new Button { Content = "📁 フォルダを選択...", HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 4, 0, 8) };
        exportDirBtn.Click += async (_, _) =>
        {
            var fp = new FolderPicker();
            fp.FileTypeFilter.Add("*");
            var hwnd = GetWindowHandle();
            if (hwnd != IntPtr.Zero) WinRT.Interop.InitializeWithWindow.Initialize(fp, hwnd);
            var f = await fp.PickSingleFolderAsync();
            if (f != null) exportDirBox.Text = f.Path;
        };

        var realtimeToggle = new ToggleSwitch { Header = "リアルタイム文字起こし", IsOn = settings.IsRealtimeEnabled, Margin = new Thickness(0, 0, 0, 8) };
        var autoDetectToggle = new ToggleSwitch { Header = "言語自動判別", IsOn = settings.IsAutoDetectEnabled, Margin = new Thickness(0, 0, 0, 8) };

        // Connection test UI
        var connectionStatusText = new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(settings.AccessKeyId) ? "未設定" : "未検証",
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var connectionStatusBadge = new Border
        {
            Background = string.IsNullOrWhiteSpace(settings.AccessKeyId)
                ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Gray)
                : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Goldenrod),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(8, 2, 8, 2),
            Child = connectionStatusText,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };

        var testConnectionBtn = new Button { Content = "接続テスト", Margin = new Thickness(0, 0, 0, 8) };
        var testProgressRing = new ProgressRing { IsActive = false, Width = 20, Height = 20, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };

        var connectionPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        connectionPanel.Children.Add(testConnectionBtn);
        connectionPanel.Children.Add(testProgressRing);
        connectionPanel.Children.Add(connectionStatusBadge);

        testConnectionBtn.Click += async (_, _) =>
        {
            testConnectionBtn.IsEnabled = false;
            testProgressRing.IsActive = true;
            connectionStatusText.Text = "テスト中...";
            connectionStatusBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Goldenrod);

            try
            {
                var testSettings = new AppSettings
                {
                    AccessKeyId = accessKeyBox.Text,
                    SecretAccessKey = secretKeyBox.Password,
                    Region = regionCombo.SelectedItem?.ToString() ?? "ap-northeast-1",
                    S3BucketName = s3Bucket.Text
                };
                var tempStore = new SettingsStore();
                var originalSettings = tempStore.Load();
                tempStore.Save(testSettings);

                try
                {
                    var client = new TranscribeClient(tempStore);
                    await client.TestConnectionAsync();
                    connectionStatusText.Text = "接続成功";
                    connectionStatusBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Green);
                }
                finally
                {
                    tempStore.Save(originalSettings);
                }
            }
            catch (AppError ex)
            {
                connectionStatusText.Text = ex.Message;
                connectionStatusBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Red);
            }
            catch (Exception ex)
            {
                connectionStatusText.Text = $"接続失敗: {ex.Message}";
                connectionStatusBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Red);
            }
            finally
            {
                testConnectionBtn.IsEnabled = true;
                testProgressRing.IsActive = false;
            }
        };

        var panel = new StackPanel { Spacing = 4, MinWidth = 700 };

        // グループ: AWS認証情報
        panel.Children.Add(CreateGroupLabel("🔑 AWS 認証情報"));
        panel.Children.Add(accessKeyBox);
        panel.Children.Add(secretKeyBox);
        panel.Children.Add(regionCombo);
        panel.Children.Add(s3Bucket);
        panel.Children.Add(connectionPanel);

        // グループ: フォルダ設定
        panel.Children.Add(CreateGroupLabel("📁 フォルダ設定"));
        panel.Children.Add(recordDirBox);
        panel.Children.Add(recordDirBtn);
        panel.Children.Add(exportDirBox);
        panel.Children.Add(exportDirBtn);

        // グループ: リアルタイム設定
        panel.Children.Add(CreateGroupLabel("🎙️ リアルタイム設定"));
        panel.Children.Add(realtimeToggle);
        panel.Children.Add(autoDetectToggle);

        var dialog = new ContentDialog
        {
            Title = "設定",
            Content = new ScrollViewer { Content = panel, MaxHeight = 600 },
            PrimaryButtonText = "保存",
            CloseButtonText = "キャンセル",
            XamlRoot = this.XamlRoot,
            MinWidth = 750
        };

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            settings.AccessKeyId = accessKeyBox.Text;
            settings.SecretAccessKey = secretKeyBox.Password;
            settings.Region = regionCombo.SelectedItem?.ToString() ?? "ap-northeast-1";
            settings.S3BucketName = s3Bucket.Text;
            settings.RecordingDirectoryPath = recordDirBox.Text;
            settings.ExportDirectoryPath = exportDirBox.Text;
            settings.IsRealtimeEnabled = realtimeToggle.IsOn;
            settings.IsAutoDetectEnabled = autoDetectToggle.IsOn;
            store.Save(settings);

            // Update realtime section visibility after settings change
            RealtimeSection.Visibility = settings.IsRealtimeEnabled
                ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private static IntPtr GetWindowHandle()
    {
        if (App.Current is App app)
        {
            var window = app.GetWindow();
            if (window != null)
                return WinRT.Interop.WindowNative.GetWindowHandle(window);
        }
        return IntPtr.Zero;
    }

    // Drag and drop
    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "ファイルをドロップ";
    }

    private async void OnDrop(object sender, DragEventArgs e)
    {
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            var items = await e.DataView.GetStorageItemsAsync();
            var file = items.OfType<StorageFile>().FirstOrDefault();
            if (file != null)
            {
                CollapseInputAndRealtime();
                _vm.ImportFileCommand.Execute(file.Path);
            }
        }
    }

    // File picker
    private async void OnFilePickClick(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.SuggestedStartLocation = PickerLocationId.MusicLibrary;
        foreach (var ext in FileImporter.SupportedExtensions)
            picker.FileTypeFilter.Add(ext);

        var hwnd = GetWindowHandle();
        if (hwnd != IntPtr.Zero)
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSingleFileAsync();
        if (file != null)
        {
            CollapseInputAndRealtime();
            _vm.ImportFileCommand.Execute(file.Path);
        }
    }

    // Copy buttons
    private void OnCopyRealtime(object sender, RoutedEventArgs e)
        => CopyToClipboard(_vm.RealtimeTranscriptionVM.FinalText + _vm.RealtimeTranscriptionVM.PartialText);

    private void OnCopyRealtimeTranslation(object sender, RoutedEventArgs e)
        => CopyToClipboard(RealtimeTranslationText.Text);

    private void OnCopyTranscript(object sender, RoutedEventArgs e)
        => CopyToClipboard(TranscriptText.Text);

    private void OnCopyTranscriptTranslation(object sender, RoutedEventArgs e)
        => CopyToClipboard(TranscriptTranslationText.Text);

    private void OnCopySummary(object sender, RoutedEventArgs e)
        => CopyToClipboard(SummaryText.Text);

    private void OnCopySummaryTranslation(object sender, RoutedEventArgs e)
        => CopyToClipboard(SummaryTranslationText.Text);

    private static void CopyToClipboard(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var dp = new DataPackage();
        dp.SetText(text);
        Clipboard.SetContent(dp);
    }

    private static Border CreateGroupLabel(string text)
    {
        return new Border
        {
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(
                Microsoft.UI.ColorHelper.FromArgb(255, 0, 120, 212)),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(10, 6, 10, 6),
            Margin = new Thickness(0, 12, 0, 4),
            Child = new TextBlock
            {
                Text = text,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                FontSize = 14,
                Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
            }
        };
    }

    // Translation handlers
    private async void OnTranslateTranscript(object sender, RoutedEventArgs e)
    {
        if (_vm.Transcript != null)
            await _vm.TranscriptTranslationVM.TranslateAsync(_vm.Transcript.Text);
    }

    private async void OnTranslateSummary(object sender, RoutedEventArgs e)
    {
        if (_vm.Summary != null)
            await _vm.SummaryTranslationVM.TranslateAsync(_vm.Summary.Text);
    }

    // 折りたたみ連動: 入力とリアルタイムを閉じる
    private void CollapseInputAndRealtime()
    {
        InputSection.IsExpanded = false;
        RealtimeSection.IsExpanded = false;
    }

    // 「ファイルから要約」ボタン
    private async void OnSummaryFileClick(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.SuggestedStartLocation = PickerLocationId.DocumentsLibrary;
        picker.FileTypeFilter.Add(".txt");

        var hwnd = GetWindowHandle();
        if (hwnd != IntPtr.Zero)
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSingleFileAsync();
        if (file != null)
        {
            CollapseInputAndRealtime();
            _vm.SummarizeFromFileCommand.Execute(file.Path);
        }
    }

    // 「要約」ボタン
    private async void OnResummarizeClick(object sender, RoutedEventArgs e)
    {
        _vm.SummaryAdditionalPrompt = SummaryPromptBox.Text;
        await _vm.ResummarizeCommand.ExecuteAsync(null);
    }

    // Error dialog
    private async void ShowErrorDialog(string message)
    {
        var dialog = new ContentDialog
        {
            Title = "エラー",
            Content = message,
            CloseButtonText = "OK",
            XamlRoot = this.XamlRoot
        };

        dialog.PrimaryButtonText = "再試行";
        dialog.PrimaryButtonClick += async (_, _) =>
        {
            await _vm.RetryLastOperationAsync();
        };

        await dialog.ShowAsync();
    }
}
