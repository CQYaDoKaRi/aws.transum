#nullable enable
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
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
        // Populate translation language ComboBoxes
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

        // Populate transcription language ComboBox
        var transcriptionLangs = Enum.GetValues<TranscriptionLanguage>();
        foreach (var lang in transcriptionLangs)
            TranscriptionLangCombo.Items.Add(lang.ToDisplayName());
        TranscriptionLangCombo.SelectedIndex = 0; // Auto
        TranscriptionLangCombo.SelectionChanged += (_, _) =>
        {
            if (TranscriptionLangCombo.SelectedIndex >= 0)
                _vm.SelectedTranscriptionLanguage = transcriptionLangs[TranscriptionLangCombo.SelectedIndex];
        };

        // Populate realtime transcription language ComboBox
        foreach (var lang in transcriptionLangs)
            RealtimeLangCombo.Items.Add(lang.ToDisplayName());
        RealtimeLangCombo.SelectedIndex = 0; // Auto
        // Auto選択時は再判別ボタンを表示
        RedetectLangBtn.Visibility = Visibility.Visible;
        RealtimeLangCombo.SelectionChanged += (_, _) =>
        {
            if (RealtimeLangCombo.SelectedIndex >= 0)
            {
                var selected = transcriptionLangs[RealtimeLangCombo.SelectedIndex];
                _vm.RealtimeTranscriptionVM.SelectedRealtimeLanguage = selected;
                // 自動検出時のみ再判別ボタンと検出言語ラベルを表示
                RedetectLangBtn.Visibility = selected == TranscriptionLanguage.Auto
                    ? Visibility.Visible : Visibility.Collapsed;
                if (selected != TranscriptionLanguage.Auto)
                    LanguageBadge.Visibility = Visibility.Collapsed;
                // ストリーミング中なら再接続
                _ = _vm.RestartRealtimeStreamingAsync();
            }
        };

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
        var loopbackIdx = _vm.AudioSources.FindIndex(s => s.IsLoopback);
        AudioSourcePicker.SelectedIndex = loopbackIdx >= 0 ? loopbackIdx : 0;

        AudioSourcePicker.SelectionChanged += (_, _) =>
        {
            if (AudioSourcePicker.SelectedItem is AudioSourceInfo src)
                _vm.SelectedSource = src;
        };

        // ファイル分割時間 ComboBox 初期化
        var splitOptions = new[] { 1, 5, 10, 15, 20, 30, 45, 60 };
        foreach (var min in splitOptions)
            SplitIntervalCombo.Items.Add($"{min}分");
        // 設定から復元
        var savedSplitIdx = Array.IndexOf(splitOptions, _vm.SplitIntervalMinutes);
        SplitIntervalCombo.SelectedIndex = savedSplitIdx >= 0 ? savedSplitIdx : Array.IndexOf(splitOptions, 30);
        SplitIntervalCombo.SelectionChanged += (_, _) =>
        {
            if (SplitIntervalCombo.SelectedIndex >= 0 && SplitIntervalCombo.SelectedIndex < splitOptions.Length)
            {
                _vm.SplitIntervalMinutes = splitOptions[SplitIntervalCombo.SelectedIndex];
                var store = new SettingsStore();
                var s = store.Load();
                s.SplitIntervalMinutes = _vm.SplitIntervalMinutes;
                store.Save(s);
            }
        };

        // Task 7.1: Hide realtime section when disabled
        var settings = new SettingsStore().Load();
        RealtimeToggle.IsOn = settings.IsRealtimeEnabled;
        RealtimeSection.Visibility = settings.IsRealtimeEnabled
            ? Visibility.Visible : Visibility.Collapsed;

        // Bedrock モデル ComboBox 初期化
        InitializeBedrockModelCombo(settings);

        // 初期状態: 音声ファイル未選択なので文字起こしボタン無効
        TranscribeButton.IsEnabled = false;
        TranscriptionLangCombo.IsEnabled = false;

        // FileList の変更を監視してUIを更新
        _vm.FileList.CollectionChanged += (_, _) => UpdateFileListUI();

        // 追加プロンプトを復元
        SummaryPromptBox.Text = _vm.SummaryAdditionalPrompt;

        // テキストエリアのリサイズ対応
        this.SizeChanged += OnPageSizeChanged;

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
                    UpdateFileListUI();
                    break;
                case nameof(MainViewModel.IsStartingCapture):
                case nameof(MainViewModel.IsStoppingCapture):
                    UpdateCaptureButtonStates();
                    break;
                case nameof(MainViewModel.Transcript):
                    TranscriptText.Text = _vm.Transcript?.Text ?? "";
                    TranscriptTranslationText.Text = "";
                    CopyTranscriptBtn.IsEnabled = !string.IsNullOrEmpty(_vm.Transcript?.Text);
                    TranslateTranscriptBtn.IsEnabled = !string.IsNullOrEmpty(_vm.Transcript?.Text);
                    CopyTranscriptTransBtn.IsEnabled = false;
                    break;
                case nameof(MainViewModel.Summary):
                    SummaryText.Text = _vm.Summary?.Text ?? "";
                    CopySummaryBtn.IsEnabled = !string.IsNullOrEmpty(_vm.Summary?.Text);
                    TranslateSummaryBtn.IsEnabled = !string.IsNullOrEmpty(_vm.Summary?.Text);
                    break;
                case nameof(MainViewModel.IsTranscribing):
                    TranscribeButton.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
                    TranscriptionLangCombo.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
                    SummaryFileBtn.IsEnabled = !_vm.IsTranscribing && !_vm.IsSummarizing;
                    ResummarizeBtn.IsEnabled = !_vm.IsTranscribing && !_vm.IsSummarizing;
                    // 文字起こし開始時に入力・リアルタイムを折りたたむ
                    if (_vm.IsTranscribing)
                    {
                        InputSection.IsExpanded = false;
                        RealtimeSection.IsExpanded = false;
                    }
                    break;
                case nameof(MainViewModel.IsSummarizing):
                    SummaryFileBtn.IsEnabled = !_vm.IsSummarizing && !_vm.IsTranscribing;
                    ResummarizeBtn.IsEnabled = !_vm.IsSummarizing && !_vm.IsTranscribing;
                    break;
                case nameof(MainViewModel.ErrorMessage):
                    if (_vm.ErrorMessage != null)
                        ShowErrorDialog(_vm.ErrorMessage);
                    break;
                case nameof(MainViewModel.ProgressMessage):
                case nameof(MainViewModel.StatusProgress):
                case nameof(MainViewModel.IsProgressIndeterminate):
                    UpdateStatusProgress();
                    break;
                case nameof(MainViewModel.AudioFile):
                    UpdateFileInfo();
                    TranscribeButton.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
                    TranscriptionLangCombo.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
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
                case nameof(MainViewModel.IsProcessing):
                    UpdateProcessingUI();
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
                    CopyRealtimeBtn.IsEnabled = !string.IsNullOrEmpty(_vm.RealtimeTranscriptionVM.FinalText);
                    ScrollRealtimeToBottom();
                    break;
                case nameof(RealtimeTranscriptionViewModel.PartialText):
                    RealtimePartialRun.Text = _vm.RealtimeTranscriptionVM.PartialText;
                    ScrollRealtimeToBottom();
                    break;
                case nameof(RealtimeTranscriptionViewModel.DetectedLanguage):
                    var lang = _vm.RealtimeTranscriptionVM.DetectedLanguage;
                    if (!string.IsNullOrEmpty(lang) &&
                        _vm.RealtimeTranscriptionVM.SelectedRealtimeLanguage == TranscriptionLanguage.Auto)
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
                    CopyRealtimeTransBtn.IsEnabled = !string.IsNullOrEmpty(_vm.RealtimeTranslationVM.TranslatedText);
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
                    CopyTranscriptTransBtn.IsEnabled = !string.IsNullOrEmpty(_vm.TranscriptTranslationVM.TranslatedText);
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
                    CopySummaryTransBtn.IsEnabled = !string.IsNullOrEmpty(_vm.SummaryTranslationVM.TranslatedText);
                    break;
                case nameof(TranslationViewModel.IsTranslating):
                    SummaryTranslateProgress.IsActive = _vm.SummaryTranslationVM.IsTranslating;
                    break;
            }
        };

        // 起動時に AWS 接続テスト → 失敗なら設定画面を開く
        _ = TestConnectionOnStartupAsync();
    }

    private async Task TestConnectionOnStartupAsync()
    {
        try
        {
            var store = new SettingsStore();
            var settings = store.Load();
            // SSO 方式の場合はキャッシュから復元を試みる
            if (settings.AuthMethod == "sso")
            {
                var ssoService = SSOAuthService.Instance;
                ssoService.RestoreFromCache();
                if (ssoService.LoginState == SSOLoginState.Authenticated)
                {
                    // キャッシュから復元成功 → 接続テスト
                    var client = new TranscribeClient(store);
                    await client.TestConnectionAsync();
                    return;
                }
                // 復元失敗 → 設定画面を開く
                OnSettingsClick(this, new RoutedEventArgs());
                return;
            }
            if (string.IsNullOrWhiteSpace(settings.AccessKeyId) && settings.AuthMethod != "awsProfile")
            {
                OnSettingsClick(this, new RoutedEventArgs());
                return;
            }
            var testClient = new TranscribeClient(store);
            await testClient.TestConnectionAsync();
        }
        catch
        {
            OnSettingsClick(this, new RoutedEventArgs());
        }
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
        SettingsButton.IsEnabled = !_vm.IsCapturing;
        FilePickButton.IsEnabled = !_vm.IsCapturing;
        DropZone.AllowDrop = !_vm.IsCapturing;
        SummaryFileBtn.IsEnabled = !_vm.IsCapturing;
        ResummarizeBtn.IsEnabled = !_vm.IsCapturing;

        SplitIntervalCombo.IsEnabled = !_vm.IsCapturing;
        AudioSourcePicker.IsEnabled = !_vm.IsCapturing;
        // 録音中は音声文字起こしエリア内の GUI を無効化
        FileListPanel.IsHitTestVisible = !_vm.IsCapturing;
        FileListPanel.Opacity = _vm.IsCapturing ? 0.5 : 1.0;
        PlayerPanel.IsHitTestVisible = !_vm.IsCapturing;
        PlayerPanel.Opacity = _vm.IsCapturing ? 0.5 : 1.0;
        TranscribeButton.IsEnabled = !_vm.IsCapturing && _vm.AudioFile != null;
        TranscriptionLangCombo.IsEnabled = !_vm.IsCapturing && _vm.AudioFile != null;

        if (_vm.IsCapturing)
        {
            InputSection.IsExpanded = true;
            RealtimeSection.IsExpanded = true;
            TranscriptSection.IsExpanded = false;
            SummarySection.IsExpanded = false;
        }
        else
        {
            InputSection.IsExpanded = false;
            RealtimeSection.IsExpanded = false;
            TranscriptSection.IsExpanded = true;
            SummarySection.IsExpanded = true;
        }
        UpdateCaptureButtonStates();
    }

    /// 録音開始中/停止中のボタン無効化状態を更新する
    private void UpdateCaptureButtonStates()
    {
        RecordButton.IsEnabled = !_vm.IsStartingCapture && !_vm.IsStoppingCapture;
        StopRecordButton.IsEnabled = !_vm.IsStartingCapture && !_vm.IsStoppingCapture;
        CancelButton.IsEnabled = !_vm.IsStartingCapture && !_vm.IsStoppingCapture;
    }

    /// <summary>処理中（文字起こし/要約）のGUI操作無効化を更新する</summary>
    private void UpdateProcessingUI()
    {
        var processing = _vm.IsProcessing;
        RecordButton.IsEnabled = !processing;
        SettingsButton.IsEnabled = !processing;
        FilePickButton.IsEnabled = !processing;
        DropZone.AllowDrop = !processing;
        AudioSourcePicker.IsEnabled = !processing;
        TranscriptionLangCombo.IsEnabled = !processing;
        BedrockModelCombo.IsEnabled = !processing;
        SummaryFileBtn.IsEnabled = !processing;
        ResummarizeBtn.IsEnabled = !processing;
        RealtimeToggle.IsEnabled = !processing;
        FileListPanel.IsHitTestVisible = !processing;
        FileListPanel.Opacity = processing ? 0.5 : 1.0;
        PlayerPanel.IsHitTestVisible = !processing;
        PlayerPanel.Opacity = processing ? 0.5 : 1.0;
    }

    private void UpdateFileInfo()
    {
        if (_vm.AudioFile != null)
        {
            var af = _vm.AudioFile;
            FileInfoText.Text = $"{af.FileName} ({af.Extension}) - {af.Duration:mm\\:ss}";
            PlayerPanel.Visibility = Visibility.Visible;
            // 波形を描画
            DrawWaveform(WaveformCanvas, _vm.WaveformData, 0);
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
        // 再生位置に応じて波形を再描画
        var progress = dur.TotalSeconds > 0 ? cur.TotalSeconds / dur.TotalSeconds : 0;
        DrawWaveform(WaveformCanvas, _vm.WaveformData, progress);
    }

    // Record / Stop / Cancel
    private async void OnRecordClick(object sender, RoutedEventArgs e) => await _vm.StartCaptureCommand.ExecuteAsync(null);
    private void OnStopRecordClick(object sender, RoutedEventArgs e) => _vm.StopCaptureCommand.Execute(null);
    private void OnCancelClick(object sender, RoutedEventArgs e) => _vm.CancelCaptureCommand.Execute(null);

    // Transcribe（FileList にファイルがある場合は複数ファイル一括文字起こし）
    private void OnTranscribeClick(object sender, RoutedEventArgs e)
    {
        _vm.SummaryAdditionalPrompt = SummaryPromptBox.Text;
        if (_vm.FileList.Count > 0)
        {
            // ファイルリストがある場合は複数ファイル一括文字起こし
            _vm.TranscribeMultipleFilesCommand.Execute(null);
        }
        else
        {
            // ファイルリストが空で audioFile がある場合は従来の文字起こし
            _vm.TranscribeAndSummarizeCommand.Execute(null);
        }
    }

    // Play/Pause
    private void OnPlayPause(object sender, RoutedEventArgs e)
        => _vm.TogglePlaybackCommand.Execute(null);

    // 波形キャンバスのポインタ操作でシーク
    private bool _isWaveformDragging;

    private void OnWaveformPointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not Canvas canvas) return;
        _isWaveformDragging = true;
        canvas.CapturePointer(e.Pointer);
        SeekFromPointer(canvas, e);
    }

    private void OnWaveformPointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_isWaveformDragging) return;
        if (sender is not Canvas canvas) return;
        SeekFromPointer(canvas, e);
    }

    /// <summary>ポインタ位置から再生位置を計算してシークする</summary>
    private void SeekFromPointer(Canvas canvas, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(canvas);
        var width = canvas.ActualWidth;
        if (width <= 0) return;
        var ratio = Math.Clamp(point.Position.X / width, 0, 1);
        var seekSeconds = ratio * _vm.AudioDuration.TotalSeconds;
        _vm.SeekCommand.Execute(seekSeconds);

        // ポインタリリース時にドラッグ終了
        if (!point.Properties.IsLeftButtonPressed)
        {
            _isWaveformDragging = false;
            canvas.ReleasePointerCapture(e.Pointer);
        }
    }

    /// <summary>Canvas 上に波形バーを描画する</summary>
    private static void DrawWaveform(Canvas canvas, float[] waveformData, double progress)
    {
        canvas.Children.Clear();
        if (waveformData == null || waveformData.Length == 0) return;

        var canvasWidth = canvas.ActualWidth;
        var canvasHeight = canvas.ActualHeight;
        if (canvasWidth <= 0 || canvasHeight <= 0) return;

        int barCount = waveformData.Length;
        // バー幅と間隔を計算
        double totalBarWidth = canvasWidth / barCount;
        double barWidth = Math.Max(1, totalBarWidth * 0.75);
        double gap = totalBarWidth - barWidth;

        // 再生済みバーの境界インデックス
        int playedBars = (int)(progress * barCount);

        var playedBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Microsoft.UI.ColorHelper.FromArgb(255, 0, 120, 212)); // #0078D4
        var unplayedBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Microsoft.UI.ColorHelper.FromArgb(255, 192, 192, 192)); // #C0C0C0

        for (int i = 0; i < barCount; i++)
        {
            var amplitude = waveformData[i];
            var barHeight = Math.Max(2, amplitude * canvasHeight);
            var x = i * totalBarWidth + gap / 2;
            var y = (canvasHeight - barHeight) / 2;

            var rect = new Microsoft.UI.Xaml.Shapes.Rectangle
            {
                Width = barWidth,
                Height = barHeight,
                Fill = i < playedBars ? playedBrush : unplayedBrush,
                RadiusX = 1,
                RadiusY = 1
            };
            Canvas.SetLeft(rect, x);
            Canvas.SetTop(rect, y);
            canvas.Children.Add(rect);
        }
    }

    // Settings dialog
    private async void OnSettingsClick(object sender, RoutedEventArgs e)
    {
        var store = new SettingsStore();
        var settings = store.Load();

        // 認証方式の状態管理
        var currentAuthMethod = settings.AuthMethod switch
        {
            "awsProfile" => "awsProfile",
            "sso" => "sso",
            _ => "accessKey"
        };

        // --- 認証方式 RadioButtons ---
        var authMethodRadio = new RadioButtons
        {
            Header = "認証方式",
            Margin = new Thickness(0, 0, 0, 8)
        };
        var accessKeyRadioItem = new RadioButton { Content = "Access Key", Tag = "accessKey" };
        var awsProfileRadioItem = new RadioButton { Content = "AWS Profile", Tag = "awsProfile" };
        var ssoRadioItem = new RadioButton { Content = "IAM Identity Center（SSO）", Tag = "sso" };
        authMethodRadio.Items.Add(accessKeyRadioItem);
        authMethodRadio.Items.Add(awsProfileRadioItem);
        authMethodRadio.Items.Add(ssoRadioItem);
        if (currentAuthMethod == "awsProfile")
            awsProfileRadioItem.IsChecked = true;
        else if (currentAuthMethod == "sso")
            ssoRadioItem.IsChecked = true;
        else
            accessKeyRadioItem.IsChecked = true;

        // --- Access Key フィールド ---
        var accessKeyBox = new TextBox { Header = "Access Key ID", Text = settings.AccessKeyId, Margin = new Thickness(0, 0, 0, 8) };
        var secretKeyBox = new PasswordBox { Header = "Secret Access Key", Password = settings.SecretAccessKey, Margin = new Thickness(0, 0, 0, 8) };
        var accessKeyPanel = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
        accessKeyPanel.Children.Add(accessKeyBox);
        accessKeyPanel.Children.Add(secretKeyBox);

        // --- AWS Profile フィールド ---
        var profileCombo = new ComboBox { Header = "プロファイル", HorizontalAlignment = HorizontalAlignment.Stretch, Margin = new Thickness(0, 0, 0, 0) };
        var profileRefreshBtn = new Button { Content = "🔄", VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(4, 0, 0, 0) };
        var profileGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        profileGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        profileGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(profileCombo, 0);
        Grid.SetColumn(profileRefreshBtn, 1);
        profileGrid.Children.Add(profileCombo);
        profileGrid.Children.Add(profileRefreshBtn);

        var profileErrorText = new TextBlock
        {
            Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange),
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        var awsProfilePanel = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
        awsProfilePanel.Children.Add(profileGrid);
        awsProfilePanel.Children.Add(profileErrorText);

        // --- SSO フィールド ---
        var ssoStartUrlBox = new TextBox
        {
            Header = "Start URL",
            Text = settings.SsoStartUrl,
            PlaceholderText = "https://my-org.awsapps.com/start",
            Margin = new Thickness(0, 0, 0, 8)
        };

        var ssoRegionCombo = new ComboBox
        {
            Header = "SSO リージョン",
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 0, 0, 8)
        };
        var ssoRegions = new[] { "us-east-1", "us-east-2", "us-west-1", "us-west-2",
            "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
            "eu-west-1", "eu-west-2", "eu-central-1", "ca-central-1" };
        foreach (var r in ssoRegions) ssoRegionCombo.Items.Add(r);
        ssoRegionCombo.SelectedItem = string.IsNullOrEmpty(settings.SsoRegion) ? "us-east-1" : settings.SsoRegion;

        var ssoLoginBtn = new Button
        {
            Content = "SSO ログイン",
            Margin = new Thickness(0, 0, 0, 8)
        };
        var ssoLoginProgress = new ProgressRing
        {
            IsActive = false,
            Width = 20,
            Height = 20,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var ssoLoginPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 4)
        };
        ssoLoginPanel.Children.Add(ssoLoginBtn);
        ssoLoginPanel.Children.Add(ssoLoginProgress);

        // User Code 表示
        var ssoUserCodeText = new TextBlock
        {
            Text = "",
            FontSize = 18,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            IsTextSelectionEnabled = true,
            Margin = new Thickness(0, 0, 0, 2),
            Visibility = Visibility.Collapsed
        };
        var ssoGuidanceText = new TextBlock
        {
            Text = "ブラウザで上記コードを入力してください",
            FontSize = 12,
            Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Gray),
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        // アカウント ComboBox
        var ssoAccountCombo = new ComboBox
        {
            Header = "アカウント",
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        // ロール ComboBox
        var ssoRoleCombo = new ComboBox
        {
            Header = "ロール",
            HorizontalAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        // 認証ステータス表示
        var ssoStatusText = new TextBlock
        {
            Text = "",
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        // SSO エラーテキスト
        var ssoErrorText = new TextBlock
        {
            Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Red),
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        // SSO ログインボタンのクリックイベント
        ssoLoginBtn.Click += async (_, _) =>
        {
            var startUrl = ssoStartUrlBox.Text?.Trim() ?? "";
            var ssoReg = ssoRegionCombo.SelectedItem?.ToString() ?? "us-east-1";

            if (string.IsNullOrEmpty(startUrl))
            {
                ssoErrorText.Text = "有効な Start URL を入力してください";
                ssoErrorText.Visibility = Visibility.Visible;
                return;
            }

            ssoErrorText.Visibility = Visibility.Collapsed;
            ssoLoginBtn.IsEnabled = false;
            ssoLoginProgress.IsActive = true;
            ssoAccountCombo.Visibility = Visibility.Collapsed;
            ssoRoleCombo.Visibility = Visibility.Collapsed;
            ssoStatusText.Visibility = Visibility.Collapsed;

            var ssoService = SSOAuthService.Instance;
            ssoService.Reset();

            // 状態変更を監視
            void OnSsoPropertyChanged(object? s, System.ComponentModel.PropertyChangedEventArgs args)
            {
                if (args.PropertyName == nameof(SSOAuthService.UserCode) && ssoService.UserCode != null)
                {
                    DispatcherQueue.TryEnqueue(() =>
                    {
                        ssoUserCodeText.Text = ssoService.UserCode;
                        ssoUserCodeText.Visibility = Visibility.Visible;
                        ssoGuidanceText.Visibility = Visibility.Visible;
                    });
                }
            }
            ssoService.PropertyChanged += OnSsoPropertyChanged;

            try
            {
                await ssoService.StartLoginAsync(startUrl, ssoReg);

                if (ssoService.LoginState == SSOLoginState.SelectingAccount)
                {
                    // 認証成功 → アカウント一覧を取得
                    await ssoService.FetchAccountsAsync();

                    if (ssoService.Accounts.Count > 0)
                    {
                        ssoAccountCombo.Items.Clear();
                        foreach (var account in ssoService.Accounts)
                            ssoAccountCombo.Items.Add(account.DisplayName);
                        ssoAccountCombo.Visibility = Visibility.Visible;

                        // 保存済みアカウントを選択
                        var savedAccountId = settings.SsoAccountId;
                        var savedIdx = ssoService.Accounts.FindIndex(a => a.AccountId == savedAccountId);
                        ssoAccountCombo.SelectedIndex = savedIdx >= 0 ? savedIdx : 0;

                        ssoStatusText.Text = "✅ 認証済み - アカウントを選択してください";
                        ssoStatusText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Green);
                        ssoStatusText.Visibility = Visibility.Visible;
                    }
                }
                else if (ssoService.LoginState == SSOLoginState.Error)
                {
                    ssoErrorText.Text = ssoService.ErrorMessage ?? "SSO ログインに失敗しました";
                    ssoErrorText.Visibility = Visibility.Visible;
                }
            }
            catch (Exception ex)
            {
                ssoErrorText.Text = $"SSO ログインに失敗しました: {ex.Message}";
                ssoErrorText.Visibility = Visibility.Visible;
            }
            finally
            {
                ssoService.PropertyChanged -= OnSsoPropertyChanged;
                ssoLoginBtn.IsEnabled = true;
                ssoLoginProgress.IsActive = false;
            }
        };

        // アカウント選択時にロール一覧を取得
        ssoAccountCombo.SelectionChanged += async (_, _) =>
        {
            if (ssoAccountCombo.SelectedIndex < 0) return;
            var ssoService = SSOAuthService.Instance;
            if (ssoAccountCombo.SelectedIndex >= ssoService.Accounts.Count) return;

            var selectedAccount = ssoService.Accounts[ssoAccountCombo.SelectedIndex];
            ssoRoleCombo.Visibility = Visibility.Collapsed;

            await ssoService.FetchRolesAsync(selectedAccount.AccountId);

            if (ssoService.Roles.Count > 0)
            {
                ssoRoleCombo.Items.Clear();
                foreach (var role in ssoService.Roles)
                    ssoRoleCombo.Items.Add(role);
                ssoRoleCombo.Visibility = Visibility.Visible;

                // 保存済みロールを選択
                var savedRole = settings.SsoRoleName;
                var savedRoleIdx = ssoService.Roles.IndexOf(savedRole);
                ssoRoleCombo.SelectedIndex = savedRoleIdx >= 0 ? savedRoleIdx : 0;
            }
            else if (ssoService.LoginState == SSOLoginState.Error)
            {
                ssoErrorText.Text = ssoService.ErrorMessage ?? "ロール一覧の取得に失敗しました";
                ssoErrorText.Visibility = Visibility.Visible;
            }
        };

        // ロール選択時に一時認証情報を取得
        ssoRoleCombo.SelectionChanged += async (_, _) =>
        {
            if (ssoRoleCombo.SelectedIndex < 0 || ssoAccountCombo.SelectedIndex < 0) return;
            var ssoService = SSOAuthService.Instance;
            if (ssoAccountCombo.SelectedIndex >= ssoService.Accounts.Count) return;
            if (ssoRoleCombo.SelectedIndex >= ssoService.Roles.Count) return;

            var selectedAccount = ssoService.Accounts[ssoAccountCombo.SelectedIndex];
            var selectedRole = ssoService.Roles[ssoRoleCombo.SelectedIndex];

            await ssoService.FetchCredentialsAsync(selectedAccount.AccountId, selectedRole);

            if (ssoService.LoginState == SSOLoginState.Authenticated)
            {
                ssoStatusText.Text = "✅ 認証済み";
                ssoStatusText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Green);
                ssoStatusText.Visibility = Visibility.Visible;
                ssoErrorText.Visibility = Visibility.Collapsed;
            }
            else if (ssoService.LoginState == SSOLoginState.Error)
            {
                ssoErrorText.Text = ssoService.ErrorMessage ?? "一時認証情報の取得に失敗しました";
                ssoErrorText.Visibility = Visibility.Visible;
            }
        };

        var ssoPanel = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
        ssoPanel.Children.Add(ssoStartUrlBox);
        ssoPanel.Children.Add(ssoRegionCombo);
        ssoPanel.Children.Add(ssoLoginPanel);
        ssoPanel.Children.Add(ssoUserCodeText);
        ssoPanel.Children.Add(ssoGuidanceText);
        ssoPanel.Children.Add(ssoErrorText);
        ssoPanel.Children.Add(ssoAccountCombo);
        ssoPanel.Children.Add(ssoRoleCombo);
        ssoPanel.Children.Add(ssoStatusText);

        // プロファイル一覧を読み込むヘルパー
        void LoadProfiles()
        {
            profileCombo.Items.Clear();
            profileErrorText.Visibility = Visibility.Collapsed;

            var configPath = AWSConfigParser.DefaultConfigPath;
            if (!System.IO.File.Exists(configPath))
            {
                profileErrorText.Text = "AWS CLI の設定ファイルが見つかりません（~/.aws/config）";
                profileErrorText.Visibility = Visibility.Visible;
                return;
            }

            var profiles = AWSConfigParser.LoadProfileNames();
            if (profiles.Count == 0)
            {
                profileErrorText.Text = "プロファイルが見つかりません";
                profileErrorText.Visibility = Visibility.Visible;
                return;
            }

            foreach (var p in profiles)
                profileCombo.Items.Add(p);

            // 保存済みプロファイルを選択
            var savedProfile = settings.AwsProfileName;
            var idx = profiles.IndexOf(savedProfile);
            profileCombo.SelectedIndex = idx >= 0 ? idx : 0;
        }

        // 認証方式に応じた表示切り替え
        void UpdateAuthMethodVisibility()
        {
            var isAccessKey = accessKeyRadioItem.IsChecked == true;
            var isAwsProfile = awsProfileRadioItem.IsChecked == true;
            var isSso = ssoRadioItem.IsChecked == true;

            accessKeyPanel.Visibility = isAccessKey ? Visibility.Visible : Visibility.Collapsed;
            awsProfilePanel.Visibility = isAwsProfile ? Visibility.Visible : Visibility.Collapsed;
            ssoPanel.Visibility = isSso ? Visibility.Visible : Visibility.Collapsed;

            if (isAwsProfile)
                LoadProfiles();
        }

        // RadioButton 変更イベント
        accessKeyRadioItem.Checked += (_, _) => UpdateAuthMethodVisibility();
        awsProfileRadioItem.Checked += (_, _) => UpdateAuthMethodVisibility();
        ssoRadioItem.Checked += (_, _) => UpdateAuthMethodVisibility();

        // リフレッシュボタン
        profileRefreshBtn.Click += (_, _) => LoadProfiles();

        // 初期表示
        UpdateAuthMethodVisibility();

        var regionCombo = new ComboBox { Header = "リージョン", Margin = new Thickness(0, 0, 0, 8), HorizontalAlignment = HorizontalAlignment.Stretch };
        var regions = new[] { "ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2",
            "us-east-1", "us-east-2", "us-west-1", "us-west-2", "eu-west-1", "eu-west-2", "eu-central-1", "ca-central-1" };
        foreach (var r in regions) regionCombo.Items.Add(r);
        regionCombo.SelectedItem = settings.Region;

        var s3Bucket = new TextBox { Header = "S3 バケット名", Text = settings.S3BucketName, Margin = new Thickness(0, 0, 0, 8) };

        var recordDirBox = new TextBox { Header = "録音保存先", Text = settings.RecordingDirectoryPath, IsReadOnly = true, HorizontalAlignment = HorizontalAlignment.Stretch };
        var recordDirBtn = new Button { Content = "📁", VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(4, 0, 0, 0) };
        var recordDirGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        recordDirGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        recordDirGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(recordDirBox, 0);
        Grid.SetColumn(recordDirBtn, 1);
        recordDirGrid.Children.Add(recordDirBox);
        recordDirGrid.Children.Add(recordDirBtn);
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
        var exportDirBtn = new Button { Content = "📁", VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(4, 0, 0, 0) };
        var exportDirGrid = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        exportDirGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        exportDirGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(exportDirBox, 0);
        Grid.SetColumn(exportDirBtn, 1);
        exportDirGrid.Children.Add(exportDirBox);
        exportDirGrid.Children.Add(exportDirBtn);
        exportDirBtn.Click += async (_, _) =>
        {
            var fp = new FolderPicker();
            fp.FileTypeFilter.Add("*");
            var hwnd = GetWindowHandle();
            if (hwnd != IntPtr.Zero) WinRT.Interop.InitializeWithWindow.Initialize(fp, hwnd);
            var f = await fp.PickSingleFolderAsync();
            if (f != null) exportDirBox.Text = f.Path;
        };

        // リアルタイム設定・要約設定は設定画面から削除済み（メイン画面で管理）

        // Connection test UI
        var connectionStatusText = new TextBlock
        {
            Text = "未検証",
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var connectionStatusBadge = new Border
        {
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Goldenrod),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(8, 2, 8, 2),
            Child = connectionStatusText,
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };

        var testConnectionBtn = new Button { Content = "接続テスト", VerticalAlignment = VerticalAlignment.Center };
        var testProgressRing = new ProgressRing { IsActive = false, Width = 20, Height = 20, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };

        var connectionPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8), VerticalAlignment = VerticalAlignment.Center };
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
                // 認証方式に応じてテスト用設定を構築
                var isAccessKeyMode = accessKeyRadioItem.IsChecked == true;
                var isSsoMode = ssoRadioItem.IsChecked == true;

                string testAuthMethod;
                if (isSsoMode)
                    testAuthMethod = "sso";
                else if (isAccessKeyMode)
                    testAuthMethod = "accessKey";
                else
                    testAuthMethod = "awsProfile";

                // SSO 方式の場合、認証済みかチェック
                if (isSsoMode)
                {
                    var ssoService = SSOAuthService.Instance;
                    if (ssoService.TemporaryCredentials == null)
                    {
                        connectionStatusText.Text = "SSO ログインを実行してください";
                        connectionStatusBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Orange);
                        testConnectionBtn.IsEnabled = true;
                        testProgressRing.IsActive = false;
                        return;
                    }
                }

                var testSettings = new AppSettings
                {
                    AuthMethod = testAuthMethod,
                    AccessKeyId = accessKeyBox.Text,
                    SecretAccessKey = secretKeyBox.Password,
                    AwsProfileName = profileCombo.SelectedItem?.ToString() ?? "",
                    Region = regionCombo.SelectedItem?.ToString() ?? "ap-northeast-1",
                    S3BucketName = s3Bucket.Text,
                    SsoStartUrl = ssoStartUrlBox.Text,
                    SsoRegion = ssoRegionCombo.SelectedItem?.ToString() ?? "",
                    SsoAccountId = ssoAccountCombo.SelectedIndex >= 0 && SSOAuthService.Instance.Accounts.Count > ssoAccountCombo.SelectedIndex
                        ? SSOAuthService.Instance.Accounts[ssoAccountCombo.SelectedIndex].AccountId : "",
                    SsoRoleName = ssoRoleCombo.SelectedItem?.ToString() ?? ""
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

        var panel = new StackPanel { Spacing = 4, MinWidth = 1050 };

        // グループ: AWS認証情報
        panel.Children.Add(CreateGroupLabel("🔑 AWS 認証情報"));
        panel.Children.Add(authMethodRadio);
        panel.Children.Add(accessKeyPanel);
        panel.Children.Add(awsProfilePanel);
        panel.Children.Add(ssoPanel);
        panel.Children.Add(regionCombo);
        panel.Children.Add(s3Bucket);
        panel.Children.Add(connectionPanel);

        // グループ: フォルダ設定
        panel.Children.Add(CreateGroupLabel("📁 フォルダ設定"));
        panel.Children.Add(recordDirGrid);
        panel.Children.Add(exportDirGrid);

        var dialog = new ContentDialog
        {
            Title = "設定",
            Content = panel,
            PrimaryButtonText = "保存",
            CloseButtonText = "キャンセル",
            XamlRoot = this.XamlRoot,
            MinWidth = 1100,
            FullSizeDesired = true
        };
        dialog.Resources["ContentDialogMaxWidth"] = 1200.0;
        dialog.Resources["ContentDialogMaxHeight"] = 1200.0;

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            // 認証方式と関連設定を保存
            if (ssoRadioItem.IsChecked == true)
                settings.AuthMethod = "sso";
            else if (awsProfileRadioItem.IsChecked == true)
                settings.AuthMethod = "awsProfile";
            else
                settings.AuthMethod = "accessKey";

            settings.AwsProfileName = profileCombo.SelectedItem?.ToString() ?? "";
            settings.AccessKeyId = accessKeyBox.Text;
            settings.SecretAccessKey = secretKeyBox.Password;
            settings.Region = regionCombo.SelectedItem?.ToString() ?? "ap-northeast-1";
            settings.S3BucketName = s3Bucket.Text;
            settings.RecordingDirectoryPath = recordDirBox.Text;
            settings.ExportDirectoryPath = exportDirBox.Text;

            // SSO 設定を永続化
            settings.SsoStartUrl = ssoStartUrlBox.Text?.Trim() ?? "";
            settings.SsoRegion = ssoRegionCombo.SelectedItem?.ToString() ?? "";
            if (ssoAccountCombo.SelectedIndex >= 0 &&
                SSOAuthService.Instance.Accounts.Count > ssoAccountCombo.SelectedIndex)
            {
                settings.SsoAccountId = SSOAuthService.Instance.Accounts[ssoAccountCombo.SelectedIndex].AccountId;
            }
            settings.SsoRoleName = ssoRoleCombo.SelectedItem?.ToString() ?? "";

            store.Save(settings);

            // 設定変更を即反映
            RealtimeToggle.IsOn = settings.IsRealtimeEnabled;
            RealtimeSection.Visibility = settings.IsRealtimeEnabled
                ? Visibility.Visible : Visibility.Collapsed;
            InitializeBedrockModelCombo(settings);
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
        if (_vm.IsCapturing) return;
        if (e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            var items = await e.DataView.GetStorageItemsAsync();
            var files = items.OfType<StorageFile>().ToList();
            if (files.Count > 0)
            {
                CollapseInputAndRealtime();
                _vm.AddFilesToList(files.Select(f => f.Path));
                UpdateFileListUI();
            }
        }
    }

    // File picker（複数選択対応、常にファイルリストに追加）
    private async void OnFilePickClick(object sender, RoutedEventArgs e)
    {
        var picker = new FileOpenPicker();
        picker.SuggestedStartLocation = PickerLocationId.MusicLibrary;
        foreach (var ext in FileImporter.SupportedExtensions)
            picker.FileTypeFilter.Add(ext);

        var hwnd = GetWindowHandle();
        if (hwnd != IntPtr.Zero)
            WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var files = await picker.PickMultipleFilesAsync();
        if (files != null && files.Count > 0)
        {
            CollapseInputAndRealtime();
            _vm.AddFilesToList(files.Select(f => f.Path));
            UpdateFileListUI();
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

    private const double MinTextAreaHeight = 150;

    private void OnPageSizeChanged(object sender, SizeChangedEventArgs e)
    {
        // ウィンドウ高さに応じてテキストエリアの高さを調整
        // 利用可能な高さからUI要素分を引いて、テキストエリアに割り当て
        var availableHeight = e.NewSize.Height;
        // CommandBar(48) + StatusBar(28) + Expander headers(4*48=192) + buttons/padding(~200) = ~468
        var overhead = 468;
        var textAreaCount = 3; // リアルタイム、文字起こし、要約の3セクション
        var calculatedHeight = Math.Max(MinTextAreaHeight, (availableHeight - overhead) / textAreaCount);

        // リアルタイム文字起こし
        var realtimeBorder = FindRealtimeBorder();
        if (realtimeBorder != null) realtimeBorder.Height = calculatedHeight;
        RealtimeTranslationText.Height = calculatedHeight;

        // 音声文字起こし
        TranscriptText.Height = calculatedHeight;
        TranscriptTranslationText.Height = calculatedHeight;

        // 要約
        SummaryText.Height = calculatedHeight;
        SummaryTranslationText.Height = calculatedHeight;
    }

    private Border? FindRealtimeBorder()
    {
        // RealtimeScrollViewerの親Border
        return RealtimeScrollViewer?.Parent as Border;
    }

    private void UpdateBedrockModelLabel(AppSettings settings)
    {
        // 基盤モデル ComboBox で管理するため不要
    }

    /// 基盤モデル ComboBox を初期化する
    private void InitializeBedrockModelCombo(AppSettings settings)
    {
        var models = BedrockModel.AvailableModels(settings.Region);
        BedrockModelCombo.Items.Clear();
        int selectedIdx = 0;
        for (int i = 0; i < models.Length; i++)
        {
            BedrockModelCombo.Items.Add(models[i].DisplayName);
            if (models[i].Id == settings.BedrockModelId)
                selectedIdx = i;
        }
        BedrockModelCombo.SelectedIndex = selectedIdx;

        BedrockModelCombo.SelectionChanged += (_, _) =>
        {
            if (BedrockModelCombo.SelectedIndex >= 0 && BedrockModelCombo.SelectedIndex < models.Length)
            {
                var store = new SettingsStore();
                var s = store.Load();
                s.BedrockModelId = models[BedrockModelCombo.SelectedIndex].Id;
                store.Save(s);
            }
        };
    }

    /// リアルタイム文字起こしトグル変更時
    private async void OnRealtimeToggled(object sender, RoutedEventArgs e)
    {
        var store = new SettingsStore();
        var s = store.Load();
        s.IsRealtimeEnabled = RealtimeToggle.IsOn;
        store.Save(s);

        if (RealtimeToggle.IsOn)
        {
            RealtimeSection.Visibility = Visibility.Visible;
            RealtimeSection.IsExpanded = true;
            TranscriptSection.IsExpanded = false;
            SummarySection.IsExpanded = false;

            // 録音中ならリアルタイム文字起こし・翻訳を開始（ストリーム出力ファイルがあれば追記）
            if (_vm.IsCapturing)
            {
                try { await StartRealtimeStreamingFromToggle(s); }
                catch (Exception ex) { _vm.RealtimeTranscriptionVM.ErrorMessage = $"ストリーミング開始エラー: {ex.Message}"; }
            }
        }
        else
        {
            RealtimeSection.Visibility = Visibility.Collapsed;
            TranscriptSection.IsExpanded = true;
            SummarySection.IsExpanded = true;

            // ストリーミング停止、テキストクリア
            _vm.StopRealtimeStreaming();
            _vm.RealtimeTranscriptionVM.FinalText = "";
            _vm.RealtimeTranscriptionVM.PartialText = "";
            _vm.RealtimeTranscriptionVM.DetectedLanguage = null;
            _vm.RealtimeTranscriptionVM.ErrorMessage = null;
            RealtimeFinalRun.Text = "";
            RealtimePartialRun.Text = "";
            CopyRealtimeBtn.IsEnabled = false;
            _vm.RealtimeTranslationVM.Reset();
            RealtimeTranslationText.Text = "";
            CopyRealtimeTransBtn.IsEnabled = false;
        }
    }

    /// 録音中にリアルタイム文字起こしを有効化した場合のストリーミング開始
    private async Task StartRealtimeStreamingFromToggle(AppSettings settings)
    {
        await _vm.StartRealtimeStreamingPublicAsync(settings);
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

    // リアルタイム文字起こし言語の再判別
    private async void OnRedetectLanguageClick(object sender, RoutedEventArgs e)
    {
        await _vm.RestartRealtimeStreamingAsync();
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

    // ファイルリスト: 全選択チェックボックス
    private void OnFileListSelectAllClick(object sender, RoutedEventArgs e)
    {
        _vm.ToggleSelectAll();
        UpdateFileListUI();
    }

    // ファイルリスト: 選択ファイル削除ボタン
    private void OnFileListRemoveClick(object sender, RoutedEventArgs e)
    {
        _vm.RemoveSelectedFiles();
        UpdateFileListUI();
    }

    // ファイルリスト: 個別チェックボックス変更
    private void OnFileListItemCheckChanged(object sender, RoutedEventArgs e)
    {
        _vm.UpdateIsAllSelected();
        UpdateFileListUI();
    }

    /// ファイルリスト行タップで再生ファイルを切り替え
    private void OnFileListItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is FileListItem item)
        {
            _vm.SelectFileForPlayback(item.AudioFile);
            UpdateFileInfo();
        }
    }

    // ファイルリスト UI の表示更新
    private void UpdateFileListUI()
    {
        FileListPanel.Visibility = _vm.FileList.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        FileListView.ItemsSource = null;
        FileListView.ItemsSource = _vm.FileList;
        FileListSelectAllCheck.IsChecked = _vm.IsAllSelected;
        TranscribeButton.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
        TranscriptionLangCombo.IsEnabled = (_vm.AudioFile != null || _vm.FileList.Count > 0) && !_vm.IsTranscribing;
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

    // ステータスバー進捗表示の更新
    private void UpdateStatusProgress()
    {
        var hasMessage = !string.IsNullOrEmpty(_vm.ProgressMessage);
        StatusProgressPanel.Visibility = hasMessage ? Visibility.Visible : Visibility.Collapsed;
        if (hasMessage)
        {
            StatusProgressText.Text = _vm.ProgressMessage;
            if (_vm.IsProgressIndeterminate)
            {
                StatusProgressBar.Visibility = Visibility.Collapsed;
                StatusProgressRing.Visibility = Visibility.Visible;
                StatusProgressRing.IsActive = true;
            }
            else
            {
                StatusProgressBar.Visibility = Visibility.Visible;
                StatusProgressBar.Value = _vm.StatusProgress;
                StatusProgressRing.Visibility = Visibility.Collapsed;
                StatusProgressRing.IsActive = false;
            }
        }
    }
}
