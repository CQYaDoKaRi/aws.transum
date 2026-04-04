#nullable enable
using System;
using System.Threading;
using System.Threading.Tasks;
using Amazon;
using Amazon.Runtime;
using Amazon.Translate;
using Amazon.Translate.Model;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// Amazon Translate ラッパー。指数バックオフ再試行付き。
/// </summary>
public class TranslateService
{
    private readonly SettingsStore _settingsStore;
    private static readonly int[] RetryDelaysMs = { 1000, 2000, 4000 };

    public TranslateService(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
    }

    /// <summary>
    /// テキストを指定言語に翻訳する。空テキストはAPI呼び出しなしで空文字を返す。
    /// </summary>
    public async Task<string> TranslateTextAsync(
        string text, string targetLanguageCode, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "";

        var settings = _settingsStore.Load();
        if (string.IsNullOrWhiteSpace(settings.AccessKeyId) ||
            string.IsNullOrWhiteSpace(settings.SecretAccessKey))
        {
            throw new AppError(AppErrorType.CredentialsNotSet,
                "AWS認証情報が設定されていません");
        }

        var credentials = new BasicAWSCredentials(settings.AccessKeyId, settings.SecretAccessKey);
        using var client = new AmazonTranslateClient(credentials,
            RegionEndpoint.GetBySystemName(settings.Region));

        var request = new TranslateTextRequest
        {
            Text = text,
            SourceLanguageCode = "auto",
            TargetLanguageCode = targetLanguageCode
        };

        // Exponential backoff retry: 1s, 2s, 4s
        for (int attempt = 0; attempt <= RetryDelaysMs.Length; attempt++)
        {
            try
            {
                ct.ThrowIfCancellationRequested();
                var response = await client.TranslateTextAsync(request, ct);
                return response.TranslatedText ?? "";
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception) when (attempt < RetryDelaysMs.Length)
            {
                await Task.Delay(RetryDelaysMs[attempt], ct);
            }
        }

        // Should not reach here, but just in case
        return "";
    }
}
