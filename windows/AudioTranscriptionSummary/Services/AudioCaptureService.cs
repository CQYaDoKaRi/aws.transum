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

    public bool IsCapturing { get; private set; }
    public float AudioLevel { get; private set; }
    public WaveFormat? CaptureWaveFormat { get; private set; }

    public event EventHandler<float>? AudioLevelChanged;
    public event EventHandler<byte[]>? DataAvailable;

    public List<AudioSourceInfo> EnumerateDevices()
    {
        var devices = new List<AudioSourceInfo>();

        // Enumerate microphone devices
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

        // Add system audio loopback
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
        _outputPath = Path.Combine(recordingDir, $"{timestamp}.wav");

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
    }

    public string StopCapture()
    {
        if (!IsCapturing || _capture == null)
            throw new InvalidOperationException("No capture in progress.");

        _capture.StopRecording();
        IsCapturing = false;

        CleanupWriter();

        return _outputPath!;
    }

    public void CancelCapture()
    {
        if (!IsCapturing || _capture == null)
            return;

        _capture.StopRecording();
        IsCapturing = false;

        CleanupWriter();

        // Delete the partial file
        if (_outputPath != null && File.Exists(_outputPath))
        {
            try { File.Delete(_outputPath); } catch { }
        }

        _outputPath = null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        _writer?.Write(e.Buffer, 0, e.BytesRecorded);

        // Calculate RMS audio level (0.0 - 1.0)
        float sum = 0;
        int sampleCount = e.BytesRecorded / 2; // 16-bit samples
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

        // Forward raw data for realtime streaming
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
