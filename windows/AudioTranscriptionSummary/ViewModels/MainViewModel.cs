#nullable enable
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AudioTranscriptionSummary.Models;
using AudioTranscriptionSummary.Services;
using Microsoft.UI.Dispatching;

namespace AudioTranscriptionSummary.ViewModels;

public partial class MainViewModel : ObservableObject
{
    private readonly SettingsStore _settingsStore;
    private readonly FileImporter _fileImporter;
    private readonly AudioCaptureService _audioCaptureService;
    private readonly AudioPlayerService _audioPlayerService;
    private readonly Summarizer _summarizer;
    private readonly ExportManager _exportManager;
    private readonly StatusMonitor _statusMonitor;
    private readonly TranscribeClient _transcribeClient;
    private readonly TranslateService _translateService;
    private readonly DispatcherQueue _dispatcherQueue;
    private readonly DispatcherQueueTimer _statusTimer;
    private readonly DispatcherQueueTimer _playerTimer;

    // Realtime streaming
    private RealtimeTranscribeClient? _realtimeClient;
    private NAudio.Wave.WaveFormat? _captureWaveFormat;

    // Retry context
    private Func<Task>? _lastOperation;

    [ObservableProperty] private AudioFile? _audioFile;
    [ObservableProperty] private Transcript? _transcript;
    [ObservableProperty] private Summary? _summary;
    [ObservableProperty] private double _transcriptionProgress;
    [ObservableProperty] private bool _isCapturing;
    [ObservableProperty] private bool _isSummarizing;
    [ObservableProperty] private bool _isTranscribing;
    [ObservableProperty] private float _audioLevel;
    [ObservableProperty] private string? _errorMessage;
    [ObservableProperty] private string _summaryAdditionalPrompt = "";
    [ObservableProperty] private bool _isPlaying;
    [ObservableProperty] private TimeSpan _playbackPosition;
    [ObservableProperty] private List<AudioSourceInfo> _audioSources = new();
    [ObservableProperty] private AudioSourceInfo? _selectedSource;
    [ObservableProperty] private TranscriptionLanguage _selectedTranscriptionLanguage = TranscriptionLanguage.Auto;

    // Status monitor display
    [ObservableProperty] private string _appCpuDisplay = "アプリ 0%";
    [ObservableProperty] private string _systemCpuDisplay = "全体 0%";
    [ObservableProperty] private string _memoryDisplay = "0 MB / 0 GB (0%)";

    // Realtime & Translation ViewModels
    public RealtimeTranscriptionViewModel RealtimeTranscriptionVM { get; }
    public TranslationViewModel RealtimeTranslationVM { get; }
    public TranslationViewModel TranscriptTranslationVM { get; }
    public TranslationViewModel SummaryTranslationVM { get; }

    public TimeSpan AudioDuration => _audioPlayerService.Duration;

    public MainViewModel()
    {
        _settingsStore = new SettingsStore();
        _fileImporter = new FileImporter();
        _audioCaptureService = new AudioCaptureService();
        _audioPlayerService = new AudioPlayerService();
        _summarizer = new Summarizer(_settingsStore);
        _exportManager = new ExportManager();
        _statusMonitor = new StatusMonitor();
        _transcribeClient = new TranscribeClient(_settingsStore);
        _translateService = new TranslateService(_settingsStore);
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread();

        RealtimeTranscriptionVM = new RealtimeTranscriptionViewModel();
        RealtimeTranslationVM = new TranslationViewModel(_translateService);
        TranscriptTranslationVM = new TranslationViewModel(_translateService);
        SummaryTranslationVM = new TranslationViewModel(_translateService);

        // Status timer (2s)
        _statusTimer = _dispatcherQueue.CreateTimer();
        _statusTimer.Interval = TimeSpan.FromSeconds(2);
        _statusTimer.Tick += (_, _) => UpdateStatus();
        _statusTimer.Start();

        // Player position timer (100ms)
        _playerTimer = _dispatcherQueue.CreateTimer();
        _playerTimer.Interval = TimeSpan.FromMilliseconds(100);
        _playerTimer.Tick += (_, _) => UpdatePlayerPosition();
        _playerTimer.Start();

        // Wire audio level events
        _audioCaptureService.AudioLevelChanged += (_, level) =>
        {
            _dispatcherQueue.TryEnqueue(() => AudioLevel = level);
        };

        _audioPlayerService.PositionChanged += (_, pos) =>
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                PlaybackPosition = pos;
                IsPlaying = _audioPlayerService.IsPlaying;
            });
        };

        LoadAudioSources();
    }

    private void LoadAudioSources()
    {
        try
        {
            AudioSources = _audioCaptureService.EnumerateDevices();
            // Default to System Audio (loopback)
            var loopback = AudioSources.Find(s => s.IsLoopback);
            SelectedSource = loopback ?? (AudioSources.Count > 0 ? AudioSources[0] : null);
        }
        catch { /* Device enumeration may fail in some environments */ }
    }

    [RelayCommand]
    private async Task ImportFileAsync(string filePath)
    {
        ErrorMessage = null;
        try
        {
            AudioFile = _fileImporter.Import(filePath);
            Transcript = null;
            Summary = null;
            _audioPlayerService.Load(filePath);
            OnPropertyChanged(nameof(AudioDuration));
            IsPlaying = false;
            PlaybackPosition = TimeSpan.Zero;
        }
        catch (AppError ex)
        {
            ErrorMessage = ex.Message;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"ファイル読み込みエラー: {ex.Message}";
        }
        await Task.CompletedTask;
    }

    [RelayCommand]
    private async Task TranscribeAndSummarizeAsync()
    {
        if (AudioFile == null) return;
        ErrorMessage = null;
        _lastOperation = TranscribeAndSummarizeAsync;
        IsTranscribing = true;

        // 文字起こし開始時にテキストクリア
        Transcript = null;
        Summary = null;
        TranscriptTranslationVM.Reset();
        SummaryTranslationVM.Reset();

        try
        {
            TranscriptionProgress = 0;
            var progress = new Progress<double>(p =>
            {
                _dispatcherQueue.TryEnqueue(() => TranscriptionProgress = p * 100);
            });

            var settings = _settingsStore.Load();
            var language = SelectedTranscriptionLanguage.ToCode();

            var transcript = await _transcribeClient.TranscribeAsync(
                AudioFile, language, progress);
            Transcript = transcript;

            IsSummarizing = true;
            try
            {
                Summary = await _summarizer.SummarizeAsync(transcript, SummaryAdditionalPrompt);
            }
            catch (AppError ex) when (ex.ErrorType == AppErrorType.InsufficientContent)
            {
                Summary = null;
            }
            IsSummarizing = false;

            if (!string.IsNullOrEmpty(settings.ExportDirectoryPath) && Transcript != null)
            {
                try { _exportManager.Export(Transcript, Summary, settings.ExportDirectoryPath, AudioFile?.FileName); }
                catch (AppError ex) { ErrorMessage = ex.Message; }
            }
        }
        catch (AppError ex) { ErrorMessage = ex.Message; ErrorLogger.SaveErrorLog(ex, "文字起こし＋要約", new Dictionary<string, string> { ["audioFile"] = AudioFile?.FileName ?? "null" }); }
        catch (Exception ex) { ErrorMessage = $"処理エラー: {ex.Message}"; ErrorLogger.SaveErrorLog(ex, "文字起こし＋要約_予期しないエラー", new Dictionary<string, string> { ["audioFile"] = AudioFile?.FileName ?? "null" }); }
        finally { IsSummarizing = false; IsTranscribing = false; }
    }

    [RelayCommand]
    private async Task ResummarizeAsync()
    {
        await SummarizeWithAvailableTextAsync();
    }

    /// <summary>
    /// 利用可能なテキスト（Transcript、リアルタイム文字起こし、または追加プロンプトのみ）でBedrock要約を実行
    /// </summary>
    private async Task SummarizeWithAvailableTextAsync()
    {
        ErrorMessage = null;

        // 1. Transcriptがあればそれを使う
        // 2. なければリアルタイム文字起こしテキストからTranscriptを生成
        // 3. どちらもなければ追加プロンプトだけでBedrockに問い合わせ
        if (Transcript == null)
        {
            var realtimeText = RealtimeTranscriptionVM.FinalText?.Trim();
            if (!string.IsNullOrEmpty(realtimeText))
            {
                Transcript = new Transcript(
                    Guid.NewGuid(),
                    AudioFile?.Id ?? Guid.NewGuid(),
                    realtimeText,
                    RealtimeTranscriptionVM.DetectedLanguage ?? "ja-JP",
                    DateTime.Now);
            }
            else
            {
                ErrorMessage = "要約するテキストがありません。文字起こしを実行するか、ファイルから読み込んでください。";
                return;
            }
        }

        IsSummarizing = true;
        // 要約開始時にクリア
        Summary = null;
        SummaryTranslationVM.Reset();
        try
        {
            Summary = await _summarizer.SummarizeAsync(Transcript, SummaryAdditionalPrompt);

            // 要約結果をファイルに保存（上書き）
            SaveSummaryToFile();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"要約に失敗しました: {ex.Message}";
            ErrorLogger.SaveErrorLog(ex, "要約失敗", new Dictionary<string, string>
            {
                ["transcriptLength"] = Transcript?.Text?.Length.ToString() ?? "0",
                ["additionalPrompt"] = SummaryAdditionalPrompt ?? ""
            });
        }
        finally
        {
            IsSummarizing = false;
        }
    }

    [RelayCommand]
    private async Task SummarizeFromFileAsync(string filePath)
    {
        ErrorMessage = null;
        try
        {
            var text = await System.IO.File.ReadAllTextAsync(filePath);
            if (string.IsNullOrWhiteSpace(text))
            {
                ErrorMessage = "ファイルが空です";
                return;
            }
            var tempTranscript = new Transcript(
                Guid.NewGuid(),
                AudioFile?.Id ?? Guid.NewGuid(),
                text,
                "auto",
                DateTime.Now
            );
            Transcript = tempTranscript;
            IsSummarizing = true;
            // 要約開始時にクリア
            Summary = null;
            SummaryTranslationVM.Reset();
            Summary = await _summarizer.SummarizeAsync(tempTranscript, SummaryAdditionalPrompt);

            // 要約結果をファイルに保存（読み込んだファイル名ベース）
            SaveSummaryToFile(System.IO.Path.GetFileName(filePath));
        }
        catch (Exception ex)
        {
            ErrorMessage = $"ファイルからの要約に失敗しました: {ex.Message}";
            ErrorLogger.SaveErrorLog(ex, "ファイルから要約失敗", new Dictionary<string, string>
            {
                ["filePath"] = filePath ?? "null"
            });
        }
        finally
        {
            IsSummarizing = false;
        }
    }

    [RelayCommand]
    private async Task ExportAsync()
    {
        if (Transcript == null) return;
        ErrorMessage = null;

        try
        {
            var settings = _settingsStore.Load();
            var dir = settings.ExportDirectoryPath;
            if (string.IsNullOrEmpty(dir))
                return;
            _exportManager.Export(Transcript, Summary, dir, AudioFile?.FileName);
        }
        catch (AppError ex)
        {
            ErrorMessage = ex.Message;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"エクスポートエラー: {ex.Message}";
        }
        await Task.CompletedTask;
    }

    [RelayCommand]
    private async Task StartCaptureAsync()
    {
        if (SelectedSource == null) return;
        ErrorMessage = null;

        // Task 6.1: Clear all text on recording start
        RealtimeTranscriptionVM.Reset();
        RealtimeTranslationVM.Reset();
        TranscriptTranslationVM.Reset();
        SummaryTranslationVM.Reset();
        Transcript = null;
        Summary = null;
        AudioFile = null;

        try
        {
            _audioCaptureService.StartCapture(SelectedSource);
            IsCapturing = true;

            // Store the capture wave format for conversion
            _captureWaveFormat = _audioCaptureService.CaptureWaveFormat;

            // Start realtime streaming if enabled
            var settings = _settingsStore.Load();
            if (settings.IsRealtimeEnabled)
            {
                await StartRealtimeStreamingAsync(settings);
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"録音開始エラー: {ex.Message}";
        }
    }

    private async Task StartRealtimeStreamingAsync(AppSettings settings)
    {
        _realtimeClient = new RealtimeTranscribeClient(_settingsStore);

        // Wire events
        _realtimeClient.PartialTranscriptReceived += (_, text) =>
        {
            _dispatcherQueue.TryEnqueue(() => RealtimeTranscriptionVM.UpdatePartialTranscript(text));
        };

        _realtimeClient.FinalTranscriptReceived += (_, text) =>
        {
            _dispatcherQueue.TryEnqueue(async () =>
            {
                RealtimeTranscriptionVM.AppendFinalTranscript(text);
                // リアルタイム翻訳: FinalText全体を翻訳
                var fullText = RealtimeTranscriptionVM.FinalText;
                if (!string.IsNullOrWhiteSpace(fullText))
                {
                    await RealtimeTranslationVM.TranslateCommand.ExecuteAsync(fullText);
                }
            });
        };

        _realtimeClient.LanguageDetected += (_, lang) =>
        {
            _dispatcherQueue.TryEnqueue(() => RealtimeTranscriptionVM.DetectedLanguage = lang);
        };

        _realtimeClient.ErrorOccurred += (_, msg) =>
        {
            _dispatcherQueue.TryEnqueue(() => RealtimeTranscriptionVM.ErrorMessage = msg);
        };

        // Subscribe to audio data
        _audioCaptureService.DataAvailable -= OnAudioDataForStreaming;
        _audioCaptureService.DataAvailable += OnAudioDataForStreaming;

        var language = SelectedTranscriptionLanguage.ToCode();
        var autoDetect = SelectedTranscriptionLanguage == TranscriptionLanguage.Auto;
        await _realtimeClient.StartStreamingAsync(language == "auto" ? "ja-JP" : language, autoDetect);
    }

    private void OnAudioDataForStreaming(object? sender, byte[] data)
    {
        if (_realtimeClient == null || _captureWaveFormat == null) return;

        try
        {
            var pcm = AudioBufferConverter.ConvertToPcm16kHz(data, _captureWaveFormat);
            _realtimeClient.SendAudioChunk(pcm);
        }
        catch
        {
            // Recording must continue even if streaming fails (Req 6.4)
        }
    }

    [RelayCommand]
    private void StopCapture()
    {
        ErrorMessage = null;
        try
        {
            // Stop realtime streaming first
            _audioCaptureService.DataAvailable -= OnAudioDataForStreaming;
            _realtimeClient?.StopStreaming();

            var filePath = _audioCaptureService.StopCapture();
            IsCapturing = false;
            AudioLevel = 0;

            // Import the recorded file
            AudioFile = _fileImporter.Import(filePath);
            _audioPlayerService.Load(filePath);
            OnPropertyChanged(nameof(AudioDuration));
            IsPlaying = false;
            PlaybackPosition = TimeSpan.Zero;

            // Realtime result stays in RealtimeTranscriptionVM only.
            // Transcript is set only by batch transcription (TranscribeAndSummarize).

            CleanupRealtimeClient();
        }
        catch (Exception ex)
        {
            IsCapturing = false;
            ErrorMessage = $"録音停止エラー: {ex.Message}";
        }
    }

    [RelayCommand]
    private void CancelCapture()
    {
        _audioCaptureService.DataAvailable -= OnAudioDataForStreaming;
        _realtimeClient?.StopStreaming();
        CleanupRealtimeClient();

        _audioCaptureService.CancelCapture();
        IsCapturing = false;
        AudioLevel = 0;
    }

    private void CleanupRealtimeClient()
    {
        _realtimeClient?.Dispose();
        _realtimeClient = null;
    }

    [RelayCommand]
    private void TogglePlayback()
    {
        if (_audioPlayerService.IsPlaying)
        {
            _audioPlayerService.Pause();
            IsPlaying = false;
        }
        else
        {
            _audioPlayerService.Play();
            IsPlaying = true;
        }
    }

    [RelayCommand]
    private void Seek(double positionSeconds)
    {
        _audioPlayerService.Seek(TimeSpan.FromSeconds(positionSeconds));
        PlaybackPosition = TimeSpan.FromSeconds(positionSeconds);
    }

    public async Task RetryLastOperationAsync()
    {
        if (_lastOperation != null)
        {
            ErrorMessage = null;
            await _lastOperation();
        }
    }

    private void SaveSummaryToFile(string? sourceFileName = null)
    {
        if (Summary == null) return;
        try
        {
            var settings = _settingsStore.Load();
            var dir = !string.IsNullOrEmpty(settings.ExportDirectoryPath)
                ? settings.ExportDirectoryPath
                : !string.IsNullOrEmpty(settings.RecordingDirectoryPath)
                    ? settings.RecordingDirectoryPath
                    : null;
            if (dir == null) return;

            if (!System.IO.Directory.Exists(dir))
                System.IO.Directory.CreateDirectory(dir);

            var baseName = sourceFileName ?? AudioFile?.FileName ?? DateTime.Now.ToString("yyyyMMdd_HHmmss");
            var ext = System.IO.Path.GetExtension(baseName);
            if (!string.IsNullOrEmpty(ext))
                baseName = System.IO.Path.GetFileNameWithoutExtension(baseName);

            var path = System.IO.Path.Combine(dir, $"{baseName}.summary.txt");
            System.IO.File.WriteAllText(path, $"=== Summary ===\n{Summary.Text}", System.Text.Encoding.UTF8);
        }
        catch (Exception ex)
        {
            ErrorLogger.SaveErrorLog(ex, "要約ファイル保存失敗", new Dictionary<string, string>
            {
                ["summaryLength"] = Summary.Text.Length.ToString()
            });
        }
    }

    private void UpdateStatus()
    {
        _statusMonitor.Update();
        AppCpuDisplay = $"アプリ {_statusMonitor.AppCpuPercent:F0}%";
        SystemCpuDisplay = $"全体 {_statusMonitor.SystemCpuPercent:F0}%";

        var appMb = _statusMonitor.AppMemoryBytes / (1024.0 * 1024.0);
        var totalGb = _statusMonitor.TotalMemoryBytes / (1024.0 * 1024.0 * 1024.0);
        var pct = _statusMonitor.TotalMemoryBytes > 0
            ? (double)_statusMonitor.AppMemoryBytes / _statusMonitor.TotalMemoryBytes * 100
            : 0;
        MemoryDisplay = $"{appMb:F0} MB / {totalGb:F1} GB ({pct:F0}%)";
    }

    private void UpdatePlayerPosition()
    {
        _audioPlayerService.UpdatePosition();
    }
}
