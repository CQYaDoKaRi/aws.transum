#nullable enable
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Amazon;
using Amazon.Runtime;
using Amazon.TranscribeStreaming;
using Amazon.TranscribeStreaming.Model;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// Amazon Transcribe Streaming APIラッパー (AWS SDK v4)。
/// PCM 16kHz 16-bit LE monoチャンクを送信し、Partial/Final結果をイベントで通知する。
/// 接続切断時は最大3回自動再接続を試みる。
/// </summary>
public class RealtimeTranscribeClient : IDisposable
{
    private readonly SettingsStore _settingsStore;
    private AmazonTranscribeStreamingClient? _client;
    private CancellationTokenSource? _cts;
    private readonly BlockingCollection<byte[]> _audioQueue = new(boundedCapacity: 500);
    private bool _isStreaming;
    private bool _disposed;
    private string _language = "ja-JP";
    private bool _autoDetect;
    private int _reconnectCount;
    private const int MaxReconnects = 3;

    public event EventHandler<string>? PartialTranscriptReceived;
    public event EventHandler<string>? FinalTranscriptReceived;
    public event EventHandler<string>? LanguageDetected;
    public event EventHandler<string>? ErrorOccurred;

    public RealtimeTranscribeClient(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
    }

    public async Task StartStreamingAsync(string language, bool autoDetect)
    {
        var settings = _settingsStore.Load();
        AWSCredentials credentials;
        try
        {
            credentials = AWSClientFactory.MakeCredentials(_settingsStore);
        }
        catch (AppError ex)
        {
            ErrorOccurred?.Invoke(this, ex.Message);
            return;
        }

        _language = language;
        _autoDetect = autoDetect;
        _reconnectCount = 0;
        _cts = new CancellationTokenSource();

        await StartStreamingInternalAsync(settings, credentials);
    }

    private Task StartStreamingInternalAsync(AppSettings settings, AWSCredentials? credentials = null)
    {
        try
        {
            // 認証情報が渡されなかった場合は AWSClientFactory から取得
            credentials ??= AWSClientFactory.MakeCredentials(_settingsStore);
            var region = AWSClientFactory.ResolveRegionEndpoint(_settingsStore);
            _client = new AmazonTranscribeStreamingClient(credentials, region);

            var request = new StartStreamTranscriptionRequest
            {
                MediaEncoding = MediaEncoding.Pcm,
                MediaSampleRateHertz = 16000,
                AudioStreamPublisher = NextAudioEventAsync,
            };

            if (_autoDetect)
            {
                request.IdentifyLanguage = true;
                request.LanguageOptions = "ja-JP,en-US";
            }
            else
            {
                request.LanguageCode = _language;
            }

            _isStreaming = true;

            // Fire-and-forget the response processing
            _ = Task.Run(async () =>
            {
                try
                {
                    var response = await _client.StartStreamTranscriptionAsync(request, _cts!.Token);
                    await ProcessResponseAsync(response, settings);
                }
                catch (OperationCanceledException)
                {
                    // Normal shutdown
                }
                catch (Exception ex)
                {
                    await HandleStreamingErrorAsync(ex, settings);
                }
            }, _cts!.Token);
        }
        catch (Exception ex)
        {
            _isStreaming = false;
            ErrorOccurred?.Invoke(this, $"ストリーミング開始エラー: {ex.Message}");
        }

        return Task.CompletedTask;
    }

    /// <summary>
    /// Called by the SDK to get the next audio event to send.
    /// Returns AudioEvent with audio data, or null when done.
    /// </summary>
    private Task<IAudioStreamEvent> NextAudioEventAsync()
    {
        try
        {
            // Block until audio data is available or collection is completed
            if (_audioQueue.TryTake(out var data, Timeout.Infinite, _cts?.Token ?? CancellationToken.None))
            {
                var audioEvent = new AudioEvent
                {
                    AudioChunk = new MemoryStream(data)
                };
                return Task.FromResult<IAudioStreamEvent>(audioEvent);
            }
        }
        catch (OperationCanceledException) { }
        catch (InvalidOperationException) { } // Collection completed

        // Signal end of stream
        return Task.FromResult<IAudioStreamEvent>(null!);
    }

    private async Task ProcessResponseAsync(StartStreamTranscriptionResponse response, AppSettings settings)
    {
        try
        {
            var resultStream = response.TranscriptResultStream;
            if (resultStream == null) return;

            var tcs = new TaskCompletionSource<bool>();

            resultStream.TranscriptEventReceived += (_, args) =>
            {
                var transcript = args.EventStreamEvent?.Transcript;
                if (transcript?.Results == null) return;

                foreach (var result in transcript.Results)
                {
                    if (result.Alternatives == null || result.Alternatives.Count == 0)
                        continue;

                    var text = result.Alternatives[0].Transcript;
                    if (string.IsNullOrEmpty(text)) continue;

                    if (result.IsPartial == true)
                    {
                        PartialTranscriptReceived?.Invoke(this, text);
                    }
                    else
                    {
                        FinalTranscriptReceived?.Invoke(this, text);
                    }

                    // Language detection
                    if (!string.IsNullOrEmpty(result.LanguageCode))
                    {
                        LanguageDetected?.Invoke(this, result.LanguageCode);
                    }
                }
            };

            resultStream.ExceptionReceived += (_, args) =>
            {
                var ex = args.EventStreamException;
                if (ex != null)
                {
                    ErrorOccurred?.Invoke(this, $"ストリーミングエラー: {ex.Message}");
                }
                tcs.TrySetResult(false);
            };

            // Start processing the event stream
            resultStream.StartProcessing();

            // Wait until cancelled
            try
            {
                await Task.Delay(Timeout.Infinite, _cts?.Token ?? CancellationToken.None);
            }
            catch (OperationCanceledException) { }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            await HandleStreamingErrorAsync(ex, settings);
        }
    }

    private async Task HandleStreamingErrorAsync(Exception ex, AppSettings settings)
    {
        if (_cts?.IsCancellationRequested == true) return;

        _reconnectCount++;
        if (_reconnectCount <= MaxReconnects)
        {
            ErrorOccurred?.Invoke(this, $"接続が切断されました。再接続中... ({_reconnectCount}/{MaxReconnects})");
            CleanupClient();
            try
            {
                await Task.Delay(1000 * _reconnectCount);
                await StartStreamingInternalAsync(settings);
            }
            catch
            {
                ErrorOccurred?.Invoke(this, "リアルタイム文字起こしの接続が切断されました。録音は継続しています");
                _isStreaming = false;
            }
        }
        else
        {
            ErrorOccurred?.Invoke(this, "リアルタイム文字起こしの接続が切断されました。録音は継続しています");
            _isStreaming = false;
        }
    }

    public void SendAudioChunk(byte[] pcmData)
    {
        if (!_isStreaming || pcmData.Length == 0) return;

        try
        {
            // Non-blocking add — drop if queue is full to avoid blocking recording
            _audioQueue.TryAdd(pcmData, 0);
        }
        catch
        {
            // Swallow — recording must continue even if streaming fails
        }
    }

    public void StopStreaming()
    {
        _isStreaming = false;
        try
        {
            _audioQueue.CompleteAdding();
        }
        catch { }

        // Give a moment for final results, then cancel
        Task.Delay(2000).ContinueWith(_ =>
        {
            _cts?.Cancel();
            CleanupClient();
        });
    }

    private void CleanupClient()
    {
        try { _client?.Dispose(); } catch { }
        _client = null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _isStreaming = false;
        _cts?.Cancel();
        try { _audioQueue.CompleteAdding(); } catch { }
        _audioQueue.Dispose();
        CleanupClient();
        _cts?.Dispose();
    }
}
