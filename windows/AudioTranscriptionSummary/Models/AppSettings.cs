using System.Text.Json.Serialization;

namespace AudioTranscriptionSummary.Models;

public class AppSettings
{
    [JsonPropertyName("accessKeyId")]
    public string AccessKeyId { get; set; } = "";

    [JsonPropertyName("secretAccessKey")]
    public string SecretAccessKey { get; set; } = "";

    [JsonPropertyName("region")]
    public string Region { get; set; } = "ap-northeast-1";

    [JsonPropertyName("s3BucketName")]
    public string S3BucketName { get; set; } = "";

    [JsonPropertyName("recordingDirectoryPath")]
    public string RecordingDirectoryPath { get; set; } = "";

    [JsonPropertyName("exportDirectoryPath")]
    public string ExportDirectoryPath { get; set; } = "";

    [JsonPropertyName("isRealtimeEnabled")]
    public bool IsRealtimeEnabled { get; set; } = true;

    [JsonPropertyName("isAutoDetectEnabled")]
    public bool IsAutoDetectEnabled { get; set; } = true;

    [JsonPropertyName("defaultTargetLanguage")]
    public string DefaultTargetLanguage { get; set; } = "ja";

    [JsonPropertyName("bedrockModelId")]
    public string BedrockModelId { get; set; } = "anthropic.claude-sonnet-4-6";

    [JsonPropertyName("summaryAdditionalPrompt")]
    public string SummaryAdditionalPrompt { get; set; } = "";

    [JsonPropertyName("splitIntervalMinutes")]
    public int SplitIntervalMinutes { get; set; } = 30;

    /// <summary>認証方式（"accessKey" または "awsProfile"）</summary>
    [JsonPropertyName("authMethod")]
    public string AuthMethod { get; set; } = "accessKey";

    /// <summary>選択された AWS プロファイル名</summary>
    [JsonPropertyName("awsProfileName")]
    public string AwsProfileName { get; set; } = "";
}
