// BedrockModel.cs
// Bedrock 基盤モデルの選択肢（Cross-Region inference 対応、macOS 版と共通）

using System.Linq;

namespace AudioTranscriptionSummary.Models;

public record BedrockModel(string Id, string Name, string Provider,
    string? UsInferenceId, string? EuInferenceId, string? GlobalInferenceId)
{
    public static readonly BedrockModel[] Available =
    [
        new("anthropic.claude-sonnet-4-6", "Claude Sonnet 4.6", "Anthropic",
            "us.anthropic.claude-sonnet-4-6", "eu.anthropic.claude-sonnet-4-6", "global.anthropic.claude-sonnet-4-6"),
        new("anthropic.claude-opus-4-6-v1", "Claude Opus 4.6", "Anthropic",
            "us.anthropic.claude-opus-4-6-v1", "eu.anthropic.claude-opus-4-6-v1", "global.anthropic.claude-opus-4-6-v1"),
        new("anthropic.claude-sonnet-4-5-20250929-v1:0", "Claude Sonnet 4.5", "Anthropic",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "eu.anthropic.claude-sonnet-4-5-20250929-v1:0", "global.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        new("anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4", "Anthropic",
            "us.anthropic.claude-sonnet-4-20250514-v1:0", "eu.anthropic.claude-sonnet-4-20250514-v1:0", "global.anthropic.claude-sonnet-4-20250514-v1:0"),
        new("anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2", "Anthropic",
            "us.anthropic.claude-3-5-sonnet-20241022-v2:0", "eu.anthropic.claude-3-5-sonnet-20241022-v2:0", null),
        new("anthropic.claude-3-5-haiku-20241022-v1:0", "Claude 3.5 Haiku", "Anthropic",
            "us.anthropic.claude-3-5-haiku-20241022-v1:0", "eu.anthropic.claude-3-5-haiku-20241022-v1:0", null),
        new("anthropic.claude-3-haiku-20240307-v1:0", "Claude 3 Haiku", "Anthropic",
            "us.anthropic.claude-3-haiku-20240307-v1:0", "eu.anthropic.claude-3-haiku-20240307-v1:0", null),
        new("amazon.titan-text-express-v1", "Titan Text Express", "Amazon",
            null, null, "amazon.titan-text-express-v1"),
        new("amazon.titan-text-lite-v1", "Titan Text Lite", "Amazon",
            null, null, "amazon.titan-text-lite-v1"),
    ];

    public static readonly string DefaultModelId = "anthropic.claude-sonnet-4-6";

    public string DisplayName => $"{Name} ({Provider})";

    public bool IsAvailable(string region)
    {
        if (region.StartsWith("us-")) return true;
        if (region.StartsWith("eu-") || region.StartsWith("il-")) return EuInferenceId != null;
        return GlobalInferenceId != null;
    }

    public string GetInferenceId(string region)
    {
        if (region.StartsWith("us-")) return UsInferenceId ?? Id;
        if (region.StartsWith("eu-") || region.StartsWith("il-")) return EuInferenceId ?? GlobalInferenceId ?? Id;
        return GlobalInferenceId ?? UsInferenceId ?? Id;
    }

    public static BedrockModel? Find(string id) => Available.FirstOrDefault(m => m.Id == id);

    public static BedrockModel[] AvailableModels(string region) => Available.Where(m => m.IsAvailable(region)).ToArray();
}
