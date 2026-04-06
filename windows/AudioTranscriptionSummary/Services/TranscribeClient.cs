#nullable enable
using System;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Amazon;
using Amazon.Runtime;
using Amazon.TranscribeService;
using Amazon.TranscribeService.Model;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

public class TranscribeClient
{
    private readonly SettingsStore _settingsStore;
    private static readonly HttpClient HttpClient = new();

    public TranscribeClient(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
    }

    public async Task<Models.Transcript> TranscribeAsync(
        AudioFile audioFile,
        string language,
        IProgress<double> progress,
        CancellationToken ct = default)
    {
        // 1. Validate credentials (progress 0.1)
        var settings = _settingsStore.Load();
        if (string.IsNullOrWhiteSpace(settings.AccessKeyId) ||
            string.IsNullOrWhiteSpace(settings.SecretAccessKey))
        {
            throw new AppError(AppErrorType.CredentialsNotSet,
                "AWS認証情報が設定されていません");
        }

        progress.Report(0.1);

        var s3Service = new S3Service(settings.AccessKeyId, settings.SecretAccessKey, settings.Region);
        var s3Key = S3Service.GenerateKey(audioFile.Extension);
        var jobName = $"ats-{Guid.NewGuid():N}";

        try
        {
            // 2. Upload to S3 (progress 0.2)
            ct.ThrowIfCancellationRequested();
            await UploadToS3(s3Service, settings.S3BucketName, s3Key, audioFile.FilePath, ct);
            progress.Report(0.2);

            // 3. Start transcription job (progress 0.4)
            ct.ThrowIfCancellationRequested();
            var s3Uri = $"s3://{settings.S3BucketName}/{s3Key}";
            var transcribeClient = CreateTranscribeServiceClient(settings);

            var startRequest = new StartTranscriptionJobRequest
            {
                TranscriptionJobName = jobName,
                MediaFormat = MapMediaFormat(audioFile.Extension),
                Media = new Media { MediaFileUri = s3Uri }
            };

            // 言語設定: "auto"の場合はIdentifyLanguageを使用
            if (language == "auto")
            {
                startRequest.IdentifyLanguage = true;
            }
            else
            {
                startRequest.LanguageCode = language;
            }

            await ExecuteWithErrorMapping(async () =>
                await transcribeClient.StartTranscriptionJobAsync(startRequest, ct));
            progress.Report(0.4);

            // 4. Poll for completion (progress 0.4-0.8)
            var resultUri = await PollForCompletion(transcribeClient, jobName, progress, ct);

            // 5. Fetch and parse result (progress 0.9)
            ct.ThrowIfCancellationRequested();
            var transcriptText = await FetchTranscriptText(resultUri, ct);
            progress.Report(0.9);

            if (string.IsNullOrWhiteSpace(transcriptText))
            {
                throw new AppError(AppErrorType.SilentAudio,
                    "音声が検出されませんでした");
            }

            var transcript = new Models.Transcript(
                Id: Guid.NewGuid(),
                AudioFileId: audioFile.Id,
                Text: transcriptText,
                Language: language,
                CreatedAt: DateTime.Now);

            return transcript;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (AppError)
        {
            throw;
        }
        catch (AmazonServiceException ex)
        {
            throw MapAmazonException(ex);
        }
        catch (Exception ex) when (ex is HttpRequestException || ex is TaskCanceledException)
        {
            throw new AppError(AppErrorType.TranscriptionFailed,
                "ネットワーク接続を確認してください", ex);
        }
        finally
        {
            // Best-effort S3 cleanup (progress 1.0)
            try
            {
                await s3Service.DeleteAsync(settings.S3BucketName, s3Key);
            }
            catch { /* best-effort */ }
            progress.Report(1.0);
        }
    }

    private async Task UploadToS3(S3Service s3, string bucket, string key, string filePath, CancellationToken ct)
    {
        try
        {
            await s3.UploadAsync(bucket, key, filePath, ct);
        }
        catch (AmazonServiceException ex)
        {
            throw MapAmazonException(ex);
        }
    }

    private async Task<string> PollForCompletion(
        AmazonTranscribeServiceClient client,
        string jobName,
        IProgress<double> progress,
        CancellationToken ct)
    {
        int pollCount = 0;
        while (true)
        {
            ct.ThrowIfCancellationRequested();
            await Task.Delay(3000, ct);
            pollCount++;

            var response = await ExecuteWithErrorMapping(async () =>
                await client.GetTranscriptionJobAsync(
                    new GetTranscriptionJobRequest { TranscriptionJobName = jobName }, ct));

            var job = response.TranscriptionJob;
            var status = job.TranscriptionJobStatus;

            if (status == TranscriptionJobStatus.COMPLETED)
            {
                progress.Report(0.8);
                return job.Transcript.TranscriptFileUri;
            }

            if (status == TranscriptionJobStatus.FAILED)
            {
                var reason = job.FailureReason ?? "不明なエラー";
                throw new AppError(AppErrorType.TranscriptionFailed,
                    $"文字起こしジョブが失敗しました: {reason}");
            }

            // Interpolate progress between 0.4 and 0.8 based on poll count
            var pollProgress = 0.4 + Math.Min(pollCount * 0.04, 0.39);
            progress.Report(pollProgress);
        }
    }

    private static async Task<string> FetchTranscriptText(string uri, CancellationToken ct)
    {
        var json = await HttpClient.GetStringAsync(uri, ct);
        using var doc = JsonDocument.Parse(json);
        var results = doc.RootElement.GetProperty("results");
        var transcripts = results.GetProperty("transcripts");
        if (transcripts.GetArrayLength() == 0)
            return "";
        return transcripts[0].GetProperty("transcript").GetString() ?? "";
    }

    private static AmazonTranscribeServiceClient CreateTranscribeServiceClient(AppSettings settings)
    {
        var credentials = new BasicAWSCredentials(settings.AccessKeyId, settings.SecretAccessKey);
        return new AmazonTranscribeServiceClient(credentials, RegionEndpoint.GetBySystemName(settings.Region));
    }

    private static string MapMediaFormat(string extension)
    {
        return extension.TrimStart('.').ToLowerInvariant() switch
        {
            "mp3" => "mp3",
            "mp4" or "m4a" => "mp4",
            "wav" => "wav",
            "flac" => "flac",
            "ogg" => "ogg",
            "webm" => "webm",
            _ => "wav"
        };
    }

    private static AppError MapAmazonException(AmazonServiceException ex)
    {
        // Auth errors
        if (ex.ErrorCode is "UnrecognizedClientException" or "InvalidSignatureException"
            or "AccessDeniedException" or "IncompleteSignature"
            or "InvalidClientTokenId" or "SignatureDoesNotMatch")
        {
            return new AppError(AppErrorType.TranscriptionFailed,
                "AWS認証情報が無効です。設定画面で確認してください", ex);
        }

        // S3 access denied
        if (ex.ErrorCode is "AccessDenied" or "AllAccessDisabled")
        {
            return new AppError(AppErrorType.TranscriptionFailed,
                "IAMポリシーを確認してください", ex);
        }

        // Network / connectivity
        if (ex.InnerException is HttpRequestException)
        {
            return new AppError(AppErrorType.TranscriptionFailed,
                "ネットワーク接続を確認してください", ex);
        }

        return new AppError(AppErrorType.TranscriptionFailed,
            $"AWS エラー: {ex.Message}", ex);
    }

    private static async Task<T> ExecuteWithErrorMapping<T>(Func<Task<T>> action)
    {
        try
        {
            return await action();
        }
        catch (AmazonServiceException ex)
        {
            throw MapAmazonException(ex);
        }
    }

    private static async Task ExecuteWithErrorMapping(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (AmazonServiceException ex)
        {
            throw MapAmazonException(ex);
        }
    }

    public async Task<bool> TestConnectionAsync()
    {
        var settings = _settingsStore.Load();
        if (string.IsNullOrWhiteSpace(settings.AccessKeyId) ||
            string.IsNullOrWhiteSpace(settings.SecretAccessKey))
        {
            throw new AppError(AppErrorType.CredentialsNotSet,
                "AWS認証情報が設定されていません");
        }

        var s3Service = new S3Service(settings.AccessKeyId, settings.SecretAccessKey, settings.Region);
        var testKey = $".connection-test-{Guid.NewGuid()}";

        try
        {
            await s3Service.UploadAsync(settings.S3BucketName, testKey,
                CreateTempTestFile());
            await s3Service.DeleteAsync(settings.S3BucketName, testKey);
            return true;
        }
        catch (AmazonServiceException ex)
        {
            throw MapAmazonException(ex);
        }
    }

    private static string CreateTempTestFile()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ats_test_{Guid.NewGuid()}.txt");
        File.WriteAllText(path, "connection-test");
        return path;
    }
}
