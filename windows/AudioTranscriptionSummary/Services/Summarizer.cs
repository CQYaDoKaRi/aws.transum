// Summarizer.cs
// Amazon Bedrock（Claude）を使用した生成型要約サービス
// AWS 認証情報未設定時はローカル抽出型要約にフォールバック

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Amazon;
using Amazon.BedrockRuntime;
using Amazon.BedrockRuntime.Model;
using Amazon.Runtime;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

public class Summarizer
{
    public const int MinimumCharacterCount = 50;

    private readonly SettingsStore _settingsStore;

    public Summarizer(SettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
    }

    public async Task<Summary> SummarizeAsync(Transcript transcript, string additionalPrompt = "")
    {
        if (transcript.Text.Length < MinimumCharacterCount)
            throw new InvalidOperationException($"要約するには内容が不十分です（最低{MinimumCharacterCount}文字必要）");

        var settings = _settingsStore.Load();

        // Bedrock で要約を試みる
        if (!string.IsNullOrEmpty(settings.AccessKeyId) && !string.IsNullOrEmpty(settings.SecretAccessKey))
        {
            try
            {
                var summaryText = await SummarizeWithBedrockAsync(transcript.Text, additionalPrompt, settings);
                return new Summary(
                    Id: Guid.NewGuid(),
                    TranscriptId: transcript.Id,
                    Text: summaryText,
                    CreatedAt: DateTime.UtcNow
                );
            }
            catch (Exception ex)
            {
                var modelId = string.IsNullOrEmpty(settings.BedrockModelId)
                    ? BedrockModel.DefaultModelId : settings.BedrockModelId;
                var logModel = BedrockModel.Find(modelId);
                ErrorLogger.SaveErrorLog(ex, "Bedrock要約失敗_フォールバック", null, new Dictionary<string, string>
                {
                    ["modelId"] = modelId,
                    ["inferenceId"] = logModel?.GetInferenceId(settings.Region) ?? modelId,
                    ["region"] = settings.Region,
                    ["textLength"] = transcript.Text.Length.ToString(),
                    ["additionalPrompt"] = additionalPrompt ?? "",
                    ["detail"] = ex.ToString()
                });
                // フォールバック: ローカル要約を実行（エラーは呼び出し元に伝播しない）
            }
        }

        // ローカル抽出型要約
        var localSummary = LocalExtractSummary(transcript.Text);
        return new Summary(
            Id: Guid.NewGuid(),
            TranscriptId: transcript.Id,
            Text: localSummary,
            CreatedAt: DateTime.UtcNow
        );
    }

    private async Task<string> SummarizeWithBedrockAsync(string text, string additionalPrompt, AppSettings settings)
    {
        var client = new AmazonBedrockRuntimeClient(
            settings.AccessKeyId,
            settings.SecretAccessKey,
            Amazon.RegionEndpoint.GetBySystemName(settings.Region)
        );

        var modelId = string.IsNullOrEmpty(settings.BedrockModelId)
            ? BedrockModel.DefaultModelId
            : settings.BedrockModelId;

        // Cross-Region inference profile IDを使用（on-demand throughput対応）
        var model = BedrockModel.Find(modelId);
        var inferenceId = model?.GetInferenceId(settings.Region) ?? modelId;

        var prompt = "以下のテキストを簡潔に要約してください。要約は元のテキストの言語で出力してください。箇条書きではなく、自然な文章で要約してください。";
        if (!string.IsNullOrWhiteSpace(additionalPrompt))
            prompt += $"\n\n追加の指示:\n{additionalPrompt}";
        prompt += $"\n\nテキスト:\n{text}";

        var request = new ConverseRequest
        {
            ModelId = inferenceId,
            Messages =
            [
                new Message
                {
                    Role = ConversationRole.User,
                    Content = [new ContentBlock { Text = prompt }]
                }
            ],
            InferenceConfig = new InferenceConfiguration
            {
                MaxTokens = 1024,
                Temperature = 0.3f
            }
        };

        var response = await client.ConverseAsync(request);
        var responseText = response.Output?.Message?.Content?.FirstOrDefault()?.Text;
        return responseText?.Trim() ?? "";
    }

    private static string LocalExtractSummary(string text)
    {
        var sentences = text.Split(['.', '。', '!', '?', '！', '？', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(s => s.Trim())
            .Where(s => s.Length > 0)
            .ToList();

        if (sentences.Count <= 1) return text.Trim();

        var count = Math.Max(1, (int)Math.Ceiling(sentences.Count * 0.3));
        return string.Join(" ", sentences.Take(count));
    }
}
