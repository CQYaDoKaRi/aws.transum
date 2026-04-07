#nullable enable
using System;
using System.Collections.Generic;
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
    private const int MaxBytesPerRequest = 9500; // Amazon Translate制限10,000バイトに安全マージン

    public TranslateService(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
    }

    /// <summary>
    /// テキストを指定言語に翻訳する。文字数制限を超える場合は文単位で分割翻訳する。
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

        // UTF-8バイト数が制限内ならそのまま翻訳
        if (System.Text.Encoding.UTF8.GetByteCount(text) <= MaxBytesPerRequest)
        {
            return await TranslateChunkAsync(client, text, targetLanguageCode, ct);
        }

        // 文単位で分割して翻訳
        var chunks = SplitBySentences(text, MaxBytesPerRequest);
        var results = new System.Text.StringBuilder();
        foreach (var chunk in chunks)
        {
            ct.ThrowIfCancellationRequested();
            var translated = await TranslateChunkAsync(client, chunk, targetLanguageCode, ct);
            results.Append(translated);
        }
        return results.ToString();
    }

    /// <summary>
    /// テキストを文単位で分割する（前後の文脈を壊さないように句点・改行で区切る）
    /// </summary>
    private static List<string> SplitBySentences(string text, int maxBytes)
    {
        var delimiters = new HashSet<char> { '。', '！', '？', '.', '!', '?', '\n' };
        var sentences = new List<string>();
        var current = new System.Text.StringBuilder();

        foreach (var ch in text)
        {
            current.Append(ch);
            if (delimiters.Contains(ch))
            {
                sentences.Add(current.ToString());
                current.Clear();
            }
        }
        if (current.Length > 0) sentences.Add(current.ToString());

        // 文をチャンクにまとめる（maxBytes以内）
        var chunks = new List<string>();
        var chunk = new System.Text.StringBuilder();
        foreach (var sentence in sentences)
        {
            var combined = chunk.ToString() + sentence;
            if (System.Text.Encoding.UTF8.GetByteCount(combined) > maxBytes && chunk.Length > 0)
            {
                chunks.Add(chunk.ToString());
                chunk.Clear();
                chunk.Append(sentence);
            }
            else
            {
                chunk.Append(sentence);
            }
        }
        if (chunk.Length > 0) chunks.Add(chunk.ToString());
        return chunks;
    }

    /// <summary>
    /// 単一チャンクを翻訳する（指数バックオフ再試行付き）
    /// </summary>
    private static async Task<string> TranslateChunkAsync(
        AmazonTranslateClient client, string text, string targetLanguageCode, CancellationToken ct)
    {
        var request = new TranslateTextRequest
        {
            Text = text,
            SourceLanguageCode = "auto",
            TargetLanguageCode = targetLanguageCode
        };

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
        return "";
    }
}
