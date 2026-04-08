#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using AudioTranscriptionSummary.Models;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace AudioTranscriptionSummary.Services;

public class AudioCaptureService : IDisposable
{
    private IWaveIn? _capture;
    private WaveFileWriter? _writer;
    private string? _outputPath;
    private bool _disposed;

    /// <summary>録音分割マネージャー</summary>
    private SplitRecordingManager? _splitManager;

    /// <summary>分割切り替え中のロックオブジェクト</summary>
    private readonly object _writerLock = new();

    public bool IsCapturing { get; private set; }
    public float AudioLevel { get; private set; }
    public WaveFormat? CaptureWaveFormat { get; private set; }

    public event EventHandler<float>? AudioLevelChanged;
    public event EventHandler<byte[]>? DataAvailable;
    /// <summary>分割ファイル確定時のコールバック（ファイルパスを通知）</summary>
    public event EventHandler<string>? FileSplitCompleted;

    public List<AudioSourceInfo> EnumerateDevices()
    {
        var devices = new List<AudioSourceInfo>();

        // マイクデバイスを列挙
        int deviceCount = WaveInEvent.DeviceCount;
        for (int i = 0; i < deviceCount; i++)
        {
            var caps = WaveInEvent.GetCapabilities(i);
            devices.Add(new AudioSourceInfo
            {
                Id = i.ToString(),
                Name = caps.ProductName,
                IsLoopback = false
            });
        }

        // システム音声ループバックを追加
        devices.Add(new AudioSourceInfo
        {
            Id = "loopback",
            Name = "System Audio",
            IsLoopback = true
        });

        return devices;
    }

    public void StartCapture(AudioSourceInfo source)
    {
        if (IsCapturing)
            throw new InvalidOperationException("Capture is already in progress.");

        var settings = new SettingsStore().Load();
        var recordingDir = !string.IsNullOrEmpty(settings.RecordingDirectoryPath)
            ? settings.RecordingDirectoryPath
            : Path.Combine(Path.GetTempPath(), "AudioTranscriptionSummary");
        if (!Directory.Exists(recordingDir))
            Directory.CreateDirectory(recordingDir);

        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");

        // SplitRecordingManager を初期化
        _splitManager = new SplitRecordingManager(timestamp, recordingDir);

        // 最初の分割ファイルパスを取得
        _outputPath = _splitManager.NextFilePath();

        if (source.IsLoopback)
        {
            var loopback = new WasapiLoopbackCapture();
            loopback.DataAvailable += OnDataAvailable;
            loopback.RecordingStopped += OnRecordingStopped;
            _writer = new WaveFileWriter(_outputPath, loopback.WaveFormat);
            CaptureWaveFormat = loopback.WaveFormat;
            _capture = loopback;
        }
        else
        {
            var mic = new WaveInEvent
            {
                DeviceNumber = int.Parse(source.Id),
                WaveFormat = new WaveFormat(44100, 16, 1)
            };
            mic.DataAvailable += OnDataAvailable;
            mic.RecordingStopped += OnRecordingStopped;
            _writer = new WaveFileWriter(_outputPath, mic.WaveFormat);
            CaptureWaveFormat = mic.WaveFormat;
            _capture = mic;
        }

        IsCapturing = true;
        _capture.StartRecording();

        // 分割タイマーを開始
        _splitManager.StartSplitting(nextPath =>
        {
            // 分割コールバック: 現在の WaveFileWriter を確定し、新しいファイルで再開
            lock (_writerLock)
            {
                try
                {
                    var completedPath = _outputPath;
                    // 現在のライターを確定
                    _writer?.Dispose();
                    _writer = null;

                    // 確定した分割ファイルを通知
                    if (!string.IsNullOrEmpty(completedPath) && File.Exists(completedPath))
                    {
                        FileSplitCompleted?.Invoke(this, completedPath!);
                    }

                    // 新しいファイルで WaveFileWriter を開始
                    _outputPath = nextPath;
                    if (CaptureWaveFormat != null)
                    {
                        _writer = new WaveFileWriter(nextPath, CaptureWaveFormat);
                    }
                }
                catch (Exception)
                {
                    // 分割ファイル書き込み失敗時は録音を継続
                }
            }
        });
    }

    /// <summary>
    /// 録音を停止し、全分割ファイルのパスリストを返す
    /// </summary>
    public List<string> StopCapture()
    {
        if (!IsCapturing || _capture == null)
            throw new InvalidOperationException("No capture in progress.");

        // 分割タイマーを停止
        _splitManager?.StopSplitting();

        _capture.StopRecording();
        IsCapturing = false;

        var lastPath = _outputPath;
        lock (_writerLock)
        {
            CleanupWriter();
        }

        // 最後の分割ファイルを通知
        if (!string.IsNullOrEmpty(lastPath) && File.Exists(lastPath))
        {
            FileSplitCompleted?.Invoke(this, lastPath!);
        }

        // 全分割ファイルのパスリストを返す
        var files = _splitManager?.SplitFiles ?? new List<string>();
        return new List<string>(files);
    }

    public void CancelCapture()
    {
        if (!IsCapturing || _capture == null)
            return;

        // 分割タイマーを停止
        _splitManager?.StopSplitting();

        _capture.StopRecording();
        IsCapturing = false;

        lock (_writerLock)
        {
            CleanupWriter();
        }

        // 分割中の全ファイルを削除
        if (_splitManager != null)
        {
            foreach (var filePath in _splitManager.SplitFiles)
            {
                try { if (File.Exists(filePath)) File.Delete(filePath); } catch { }
            }
            _splitManager.Reset();
        }

        _outputPath = null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_writerLock)
        {
            _writer?.Write(e.Buffer, 0, e.BytesRecorded);
        }

        // RMS 音声レベルを計算（0.0 - 1.0）
        float sum = 0;
        int sampleCount = e.BytesRecorded / 2; // 16ビットサンプル
        if (sampleCount > 0)
        {
            for (int i = 0; i < e.BytesRecorded; i += 2)
            {
                if (i + 1 < e.BytesRecorded)
                {
                    short sample = (short)(e.Buffer[i] | (e.Buffer[i + 1] << 8));
                    float normalized = sample / 32768f;
                    sum += normalized * normalized;
                }
            }

            float rms = MathF.Sqrt(sum / sampleCount);
            AudioLevel = Math.Clamp(rms, 0f, 1f);
            AudioLevelChanged?.Invoke(this, AudioLevel);
        }

        // リアルタイムストリーミング用に生データを転送
        if (e.BytesRecorded > 0)
        {
            var data = new byte[e.BytesRecorded];
            Array.Copy(e.Buffer, data, e.BytesRecorded);
            DataAvailable?.Invoke(this, data);
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        CleanupCapture();
    }

    private void CleanupWriter()
    {
        _writer?.Dispose();
        _writer = null;
    }

    private void CleanupCapture()
    {
        if (_capture != null)
        {
            _capture.Dispose();
            _capture = null;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (IsCapturing)
            CancelCapture();

        CleanupWriter();
        CleanupCapture();
    }
}
