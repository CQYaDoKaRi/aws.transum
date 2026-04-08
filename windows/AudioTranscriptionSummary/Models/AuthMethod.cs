// AuthMethod.cs
// AWS 認証方式を表す列挙型

namespace AudioTranscriptionSummary.Models;

/// <summary>
/// AWS 認証方式を表す列挙型
/// - AccessKey: Access Key ID / Secret Access Key による手動入力方式
/// - AwsProfile: AWS CLI プロファイル選択方式（SSO / AssumeRole 対応）
/// </summary>
public enum AuthMethod
{
    /// <summary>Access Key ID / Secret Access Key による手動入力方式</summary>
    AccessKey,

    /// <summary>AWS CLI プロファイル選択方式</summary>
    AwsProfile
}
