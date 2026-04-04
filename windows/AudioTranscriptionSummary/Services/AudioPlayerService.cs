#nullable enable
using System;
using NAudio.Wave;

namespace AudioTranscriptionSummary.Services;

public class AudioPlayerService : IDisposable
{
    private WaveOutEvent? _waveOut;
    private AudioFileReader? _reader;
    private bool _disposed;

    public bool IsPlaying { get; private set; }
    public TimeSpan CurrentTime => _reader?.CurrentTime ?? TimeSpan.Zero;
    public TimeSpan Duration => _reader?.TotalTime ?? TimeSpan.Zero;

    public event EventHandler<TimeSpan>? PositionChanged;

    public void Load(string filePath)
    {
        Cleanup();

        _reader = new AudioFileReader(filePath);
        _waveOut = new WaveOutEvent();
        _waveOut.Init(_reader);
        _waveOut.PlaybackStopped += OnPlaybackStopped;
    }

    public void Play()
    {
        if (_waveOut == null || _reader == null) return;

        // If at end, reset to beginning
        if (_reader.CurrentTime >= _reader.TotalTime)
            _reader.CurrentTime = TimeSpan.Zero;

        _waveOut.Play();
        IsPlaying = true;
    }

    public void Pause()
    {
        if (_waveOut == null) return;

        _waveOut.Pause();
        IsPlaying = false;
    }

    public void Seek(TimeSpan position)
    {
        if (_reader == null) return;

        _reader.CurrentTime = position > _reader.TotalTime
            ? _reader.TotalTime
            : position < TimeSpan.Zero
                ? TimeSpan.Zero
                : position;

        PositionChanged?.Invoke(this, _reader.CurrentTime);
    }

    /// <summary>
    /// Called by a DispatcherTimer (100ms interval) from the ViewModel to update position.
    /// </summary>
    public void UpdatePosition()
    {
        if (_reader != null && IsPlaying)
        {
            PositionChanged?.Invoke(this, _reader.CurrentTime);

            // Auto-stop at end
            if (_reader.CurrentTime >= _reader.TotalTime)
            {
                _waveOut?.Stop();
                IsPlaying = false;
                _reader.CurrentTime = TimeSpan.Zero;
                PositionChanged?.Invoke(this, TimeSpan.Zero);
            }
        }
    }

    private void OnPlaybackStopped(object? sender, StoppedEventArgs e)
    {
        IsPlaying = false;
    }

    private void Cleanup()
    {
        if (_waveOut != null)
        {
            _waveOut.PlaybackStopped -= OnPlaybackStopped;
            _waveOut.Stop();
            _waveOut.Dispose();
            _waveOut = null;
        }

        if (_reader != null)
        {
            _reader.Dispose();
            _reader = null;
        }

        IsPlaying = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Cleanup();
    }
}
