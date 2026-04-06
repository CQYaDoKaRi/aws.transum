// BedrockModel.cs
// Bedrock 基盤モデルの選択肢（macOS 版と共通）

namespace AudioTranscriptionSummary.Models;

public record BedrockModel(string Id, string Name, string Provider)
{
    public static readonly BedrockModel[] Available =
    [
        // Claude 4.x 系（最新）
        new("anthropic.claude-sonnet-4-6-20260617-v1:0", "Claude Sonnet 4.6", "Anthropic"),
        new("anthropic.claude-opus-4-6-20260514-v1:0", "Claude Opus 4.6", "Anthropic"),
        new("anthropic.claude-sonnet-4-5-20250929-v1:0", "Claude Sonnet 4.5", "Anthropic"),
        new("anthropic.claude-opus-4-5-20251101-v1:0", "Claude Opus 4.5", "Anthropic"),
        new("anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4", "Anthropic"),
        // Claude 3.x 系
        new("anthropic.claude-3-5-sonnet-20241022-v2:0", "Claude 3.5 Sonnet v2", "Anthropic"),
        new("anthropic.claude-3-5-haiku-20241022-v1:0", "Claude 3.5 Haiku", "Anthropic"),
        new("anthropic.claude-3-haiku-20240307-v1:0", "Claude 3 Haiku", "Anthropic"),
        new("anthropic.claude-3-sonnet-20240229-v1:0", "Claude 3 Sonnet", "Anthropic"),
        // Amazon Titan
        new("amazon.titan-text-express-v1", "Titan Text Express", "Amazon"),
        new("amazon.titan-text-lite-v1", "Titan Text Lite", "Amazon"),
    ];

    public static readonly string DefaultModelId = "anthropic.claude-sonnet-4-6-20260617-v1:0";

    public string DisplayName => $"{Name} ({Provider})";
}
