#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
    private DateTime? _captureStartTime;

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

    // ファイルリスト（複数ファイル文字起こし用）
    [ObservableProperty] private System.Collections.ObjectModel.ObservableCollection<FileListItem> _fileList = new();
    [ObservableProperty] private bool _isAllSelected;

    // 録音開始中/停止中フラグ（ボタン無効化用）
    [ObservableProperty] private bool _isStartingCapture;
    [ObservableProperty] private bool _isStoppingCapture;

    /// ファイル分割間隔（分）。1〜60、デフォルト30分
    [ObservableProperty] private int _splitIntervalMinutes = 30;

    // ステータスバー進捗表示
    [ObservableProperty] private string? _progressMessage;
    [ObservableProperty] private double _statusProgress;
    [ObservableProperty] private bool _isProgressIndeterminate;

    // 波形データ（波形表示用）
    [ObservableProperty] private float[] _waveformData = Array.Empty<float>();

    // Status monitor display
    [ObservableProperty] private string _appCpuDisplay = "アプリ 0%";
    [ObservableProperty] private string _systemCpuDisplay = "全体 0%";
    [ObservableProperty] private string _memoryDisplay = "0 MB / 0 GB (0%)";

    /// <summary>処理中かどうか（文字起こし中 または 要約中）</summary>
    public bool IsProcessing => IsTranscribing || IsSummarizing;

    partial void OnIsTranscribingChanged(bool value)
    {
        OnPropertyChanged(nameof(IsProcessing));
    }

    partial void OnIsSummarizingChanged(bool value)
    {
        OnPropertyChanged(nameof(IsProcessing));
    }

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

        // 分割ファイル確定時にファイルリストへ自動登録
        _audioCaptureService.FileSplitCompleted += (_, filePath) =>
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                try
                {
                    var file = _fileImporter.Import(filePath);
                    FileList.Add(new FileListItem(file, isSelected: true));
                }
                catch { /* 分割ファイル読み込み失敗は無視 */ }
            });
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

        // 追加プロンプトを設定から復元
        var savedSettings = _settingsStore.Load();
        SummaryAdditionalPrompt = savedSettings.SummaryAdditionalPrompt;
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
            // 波形データを生成
            WaveformData = WaveformDataProvider.LoadWaveformData(filePath);
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
        ProgressMessage = "文字起こし中...";
        IsProgressIndeterminate = false;

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
                _dispatcherQueue.TryEnqueue(() =>
                {
                    TranscriptionProgress = p * 100;
                    StatusProgress = p * 100;
                    ProgressMessage = $"文字起こし中... {p * 100:F0}%";
                });
            });

            var settings = _settingsStore.Load();
            var language = SelectedTranscriptionLanguage.ToCode();

            var transcript = await _transcribeClient.TranscribeAsync(
                AudioFile, language, progress);
            Transcript = transcript;

            IsSummarizing = true;
            ProgressMessage = "要約を生成中...";
            IsProgressIndeterminate = true;
            StatusProgress = 0;
            SaveAdditionalPrompt();
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
        catch (AppError ex) { ErrorMessage = ex.Message; ErrorLogger.SaveErrorLog(ex, "文字起こし＋要約", AudioFile?.FileName); }
        catch (Exception ex) { ErrorMessage = $"処理エラー: {ex.Message}"; ErrorLogger.SaveErrorLog(ex, "文字起こし＋要約_予期しないエラー", AudioFile?.FileName); }
        finally { IsSummarizing = false; IsTranscribing = false; ProgressMessage = null; }
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
        ProgressMessage = "要約を生成中...";
        IsProgressIndeterminate = true;
        StatusProgress = 0;
        // 追加プロンプトを設定に保存
        SaveAdditionalPrompt();
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
            ErrorLogger.SaveErrorLog(ex, "要約失敗", AudioFile?.FileName, new Dictionary<string, string>
            {
                ["transcriptLength"] = Transcript?.Text?.Length.ToString() ?? "0",
                ["additionalPrompt"] = SummaryAdditionalPrompt ?? ""
            });
        }
        finally
        {
            IsSummarizing = false;
            ProgressMessage = null;
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
            ProgressMessage = "要約を生成中...";
            IsProgressIndeterminate = true;
            StatusProgress = 0;
            SaveAdditionalPrompt();
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
            ErrorLogger.SaveErrorLog(ex, "ファイルから要約失敗", System.IO.Path.GetFileName(filePath));
        }
        finally
        {
            IsSummarizing = false;
            ProgressMessage = null;
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
        IsStartingCapture = true;
        ProgressMessage = "録音開始中...";
        IsProgressIndeterminate = true;

        // Task 6.1: Clear all text on recording start
        RealtimeTranscriptionVM.Reset();
        RealtimeTranslationVM.Reset();
        TranscriptTranslationVM.Reset();
        SummaryTranslationVM.Reset();
        Transcript = null;
        Summary = null;
        AudioFile = null;
        FileList.Clear();

        // リアルタイム文字起こしのストリーム出力パスを設定
        var captureSettings = _settingsStore.Load();
        var recordingDir = !string.IsNullOrEmpty(captureSettings.RecordingDirectoryPath)
            ? captureSettings.RecordingDirectoryPath
            : System.IO.Path.Combine(System.IO.Path.GetTempPath(), "AudioTranscriptionSummary");
        if (!System.IO.Directory.Exists(recordingDir))
            System.IO.Directory.CreateDirectory(recordingDir);
        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        RealtimeTranscriptionVM.StreamOutputPath = System.IO.Path.Combine(recordingDir, $"{timestamp}.transcribe.stream.txt");

        try
        {
            _audioCaptureService.StartCapture(SelectedSource, SplitIntervalMinutes);
            IsCapturing = true;
            IsStartingCapture = false;
            _captureStartTime = DateTime.Now;
            ProgressMessage = "音声をキャプチャ中... 00:00";
            IsProgressIndeterminate = true;
            StatusProgress = 0;

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
            IsStartingCapture = false;
            ProgressMessage = null;
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
                // リアルタイム翻訳: 文字起こし言語と翻訳先言語が異なる場合のみ実行
                if (!string.IsNullOrWhiteSpace(text))
                {
                    var targetCode = RealtimeTranslationVM.SelectedTargetLanguage.ToCode();
                    string transcribeLangPrefix;
                    if (RealtimeTranscriptionVM.SelectedRealtimeLanguage != TranscriptionLanguage.Auto)
                    {
                        // 指定言語モード: 選択言語のプレフィックス
                        var code = RealtimeTranscriptionVM.SelectedRealtimeLanguage.ToCode();
                        transcribeLangPrefix = code.Length >= 2 ? code[..2].ToLower() : "";
                    }
                    else
                    {
                        // 自動検出モード: 検出された言語のプレフィックス
                        var detected = RealtimeTranscriptionVM.DetectedLanguage ?? "";
                        transcribeLangPrefix = detected.Length >= 2 ? detected[..2].ToLower() : "";
                    }
                    if (!string.IsNullOrEmpty(transcribeLangPrefix) && transcribeLangPrefix != targetCode)
                    {
                        var fullText = RealtimeTranscriptionVM.FinalText;
                        await RealtimeTranslationVM.TranslateCommand.ExecuteAsync(fullText);
                    }
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

        var realtimeLang = RealtimeTranscriptionVM.SelectedRealtimeLanguage;
        var language = realtimeLang.ToCode();
        var autoDetect = realtimeLang == TranscriptionLanguage.Auto;
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
        IsStoppingCapture = true;
        ProgressMessage = "録音停止中...";
        IsProgressIndeterminate = true;
        try
        {
            // Stop realtime streaming first
            _audioCaptureService.DataAvailable -= OnAudioDataForStreaming;
            _realtimeClient?.StopStreaming();

            var filePaths = _audioCaptureService.StopCapture();
            IsCapturing = false;
            IsStoppingCapture = false;
            _captureStartTime = null;
            ProgressMessage = null;
            AudioLevel = 0;

            // fileList への追加は FileSplitCompleted イベントで実施済み

            // 最初のファイルをプレーヤーに読み込み
            if (FileList.Count > 0)
            {
                var firstFile = FileList[0].AudioFile;
                AudioFile = firstFile;
                _audioPlayerService.Load(firstFile.FilePath);
                OnPropertyChanged(nameof(AudioDuration));
                IsPlaying = false;
                PlaybackPosition = TimeSpan.Zero;
                WaveformData = WaveformDataProvider.LoadWaveformData(firstFile.FilePath);
            }

            CleanupRealtimeClient();
        }
        catch (Exception ex)
        {
            IsCapturing = false;
            IsStoppingCapture = false;
            ProgressMessage = null;
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
        _captureStartTime = null;
        ProgressMessage = null;
        AudioLevel = 0;
    }

    // MARK: - ファイルリスト操作

    /// ファイルリストにファイルを追加する
    /// FileImporter で各パスを読み込み、FileListItem として末尾に追加する
    public void AddFilesToList(IEnumerable<string> filePaths)
    {
        var errors = new List<string>();
        foreach (var filePath in filePaths)
        {
            try
            {
                var audioFile = _fileImporter.Import(filePath);
                var item = new FileListItem(audioFile);
                FileList.Add(item);
            }
            catch (Exception ex)
            {
                errors.Add($"{Path.GetFileName(filePath)}: {ex.Message}");
            }
        }
        if (errors.Count > 0)
        {
            ErrorMessage = "一部のファイルを追加できませんでした:\n" + string.Join("\n", errors);
        }
        UpdateIsAllSelected();
    }

    /// ファイルリストの全選択/全解除をトグルする
    public void ToggleSelectAll()
    {
        var hasAnySelected = FileList.Any(f => f.IsSelected);
        foreach (var item in FileList)
        {
            item.IsSelected = !hasAnySelected;
        }
        UpdateIsAllSelected();
    }

    /// ファイルリストから選択中のファイルを削除する
    public void RemoveSelectedFiles()
    {
        var toRemove = FileList.Where(f => f.IsSelected).ToList();
        foreach (var item in toRemove)
        {
            FileList.Remove(item);
        }
        UpdateIsAllSelected();
    }

    /// IsAllSelected を更新する
    public void UpdateIsAllSelected()
    {
        IsAllSelected = FileList.Count > 0 && FileList.All(f => f.IsSelected);
    }

    /// ファイルリストの行タップで再生ファイルを切り替える
    public void SelectFileForPlayback(AudioFile file)
    {
        AudioFile = file;
        try
        {
            _audioPlayerService.Load(file.FilePath);
            OnPropertyChanged(nameof(AudioDuration));
            IsPlaying = false;
            PlaybackPosition = TimeSpan.Zero;
            // 波形データを生成
            WaveformData = WaveformDataProvider.LoadWaveformData(file.FilePath);
        }
        catch { /* プレーヤー読み込み失敗は無視 */ }
    }

    // MARK: - 複数ファイル一括文字起こし

    /// ファイルリストで選択されたファイルを逐次文字起こしし、結果を結合する
    [RelayCommand]
    private async Task TranscribeMultipleFilesAsync()
    {
        var selectedFiles = FileList.Where(f => f.IsSelected).ToList();
        if (selectedFiles.Count == 0) return;

        // 状態をリセット
        ErrorMessage = null;
        _lastOperation = TranscribeMultipleFilesAsync;
        IsTranscribing = true;
        TranscriptionProgress = 0;
        IsProgressIndeterminate = false;
        Transcript = null;
        Summary = null;
        TranscriptTranslationVM.Reset();
        SummaryTranslationVM.Reset();

        var totalCount = (double)selectedFiles.Count;
        var results = new List<string>();
        var errors = new List<string>();

        for (int index = 0; index < selectedFiles.Count; index++)
        {
            var item = selectedFiles[index];
            var i = (double)index;

            try
            {
                var progress = new Progress<double>(p =>
                {
                    _dispatcherQueue.TryEnqueue(() =>
                    {
                        // 全体進捗: (i + p) / N
                        var overallProgress = (i + p) / totalCount;
                        TranscriptionProgress = overallProgress * 100;
                        StatusProgress = overallProgress * 100;
                        ProgressMessage = $"文字起こし中... ({index + 1}/{selectedFiles.Count}) {overallProgress * 100:F0}%";
                    });
                });

                var language = SelectedTranscriptionLanguage.ToCode();
                var transcript = await _transcribeClient.TranscribeAsync(item.AudioFile, language, progress);
                results.Add(transcript.Text);
            }
            catch (Exception ex)
            {
                errors.Add($"{item.AudioFile.FileName}: {ex.Message}");
            }

            // ファイル完了時の進捗更新
            TranscriptionProgress = ((i + 1) / totalCount) * 100;
            StatusProgress = TranscriptionProgress;
        }

        // エラーメッセージの記録
        if (errors.Count > 0)
        {
            ErrorMessage = "一部のファイルで文字起こしに失敗しました:\n" + string.Join("\n", errors);
        }

        // 結果テキストをファイル順に結合して transcript にセット
        if (results.Count > 0)
        {
            var combinedText = string.Join("\n", results);
            var firstFile = selectedFiles[0].AudioFile;
            Transcript = new Transcript(
                Guid.NewGuid(),
                firstFile.Id,
                combinedText,
                SelectedTranscriptionLanguage.ToCode(),
                DateTime.Now);
        }

        TranscriptionProgress = 100;
        IsTranscribing = false;

        // 結合結果を .transcript.txt ファイルとして保存
        if (Transcript != null)
        {
            try
            {
                var settings = _settingsStore.Load();
                var dir = !string.IsNullOrEmpty(settings.ExportDirectoryPath)
                    ? settings.ExportDirectoryPath
                    : !string.IsNullOrEmpty(settings.RecordingDirectoryPath)
                        ? settings.RecordingDirectoryPath
                        : null;
                if (dir != null)
                {
                    if (!Directory.Exists(dir))
                        Directory.CreateDirectory(dir);
                    var baseName = Path.GetFileNameWithoutExtension(selectedFiles[0].AudioFile.FileName);
                    var transcriptPath = Path.Combine(dir, $"{baseName}.transcript.txt");
                    await File.WriteAllTextAsync(transcriptPath, Transcript.Text, System.Text.Encoding.UTF8);
                }
            }
            catch (Exception ex)
            {
                ErrorLogger.SaveErrorLog(ex, "文字起こしファイル保存失敗");
            }
        }

        // 要約も自動実行する
        if (Transcript != null)
        {
            IsSummarizing = true;
            ProgressMessage = "要約を生成中...";
            IsProgressIndeterminate = true;
            StatusProgress = 0;
            SaveAdditionalPrompt();
            try
            {
                Summary = await _summarizer.SummarizeAsync(Transcript, SummaryAdditionalPrompt);
            }
            catch (AppError ex) when (ex.ErrorType == AppErrorType.InsufficientContent)
            {
                Summary = null;
            }
            catch (Exception ex)
            {
                ErrorMessage = (ErrorMessage != null ? ErrorMessage + "\n" : "") + $"要約に失敗しました: {ex.Message}";
            }
            IsSummarizing = false;

            // 要約結果をファイルに保存
            SaveSummaryToFile(selectedFiles[0].AudioFile.FileName);
        }

        ProgressMessage = null;
    }

    private void CleanupRealtimeClient()
    {
        _realtimeClient?.Dispose();
        _realtimeClient = null;
    }

    /// <summary>
    /// リアルタイム文字起こしの言語変更時にストリーミングを再接続する。
    /// 確定テキスト（FinalText）は保持し、暫定テキスト（PartialText）はクリアする。
    /// </summary>
    public async Task RestartRealtimeStreamingAsync()
    {
        if (!IsCapturing || _realtimeClient == null) return;

        // 現在のストリーミングを停止
        _realtimeClient.StopStreaming();
        CleanupRealtimeClient();

        // 暫定テキストをクリア（確定テキストは保持）
        RealtimeTranscriptionVM.PartialText = "";
        RealtimeTranscriptionVM.ErrorMessage = null;

        // 新しい言語設定でストリーミング再開
        try
        {
            var settings = _settingsStore.Load();
            await StartRealtimeStreamingAsync(settings);
        }
        catch (Exception ex)
        {
            RealtimeTranscriptionVM.ErrorMessage = $"ストリーミング再接続エラー: {ex.Message}";
        }
    }

    /// <summary>
    /// リアルタイム文字起こしを停止する（トグル無効化時に使用）
    /// </summary>
    public void StopRealtimeStreaming()
    {
        _audioCaptureService.DataAvailable -= OnAudioDataForStreaming;
        _realtimeClient?.StopStreaming();
        CleanupRealtimeClient();
    }

    /// <summary>
    /// 録音中にリアルタイム文字起こしを有効化した場合のストリーミング開始（public）
    /// </summary>
    public async Task StartRealtimeStreamingPublicAsync(AppSettings settings)
    {
        await StartRealtimeStreamingAsync(settings);
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
            ErrorLogger.SaveErrorLog(ex, "要約ファイル保存失敗", AudioFile?.FileName);
        }
    }

    private void SaveAdditionalPrompt()
    {
        try
        {
            var settings = _settingsStore.Load();
            settings.SummaryAdditionalPrompt = SummaryAdditionalPrompt;
            _settingsStore.Save(settings);
        }
        catch { /* 設定保存失敗は無視 */ }
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

        // 録音中は録音時間を表示
        if (IsCapturing && _captureStartTime.HasValue)
        {
            var elapsed = DateTime.Now - _captureStartTime.Value;
            ProgressMessage = $"音声をキャプチャ中... {elapsed:mm\\:ss}";
        }
    }

    private void UpdatePlayerPosition()
    {
        _audioPlayerService.UpdatePosition();
    }
}
