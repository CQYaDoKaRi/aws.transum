// SSOModels.cs
// IAM Identity Center（SSO）認証に関連するデータモデル

using System;

namespace AudioTranscriptionSummary.Models;

/// <summary>
/// SSO 認証フローの状態を表す列挙型
/// </summary>
public enum SSOLoginState
{
    /// <summary>初期状態（未認証）</summary>
    Idle,
    /// <summary>RegisterClient API 呼び出し中</summary>
    Registering,
    /// <summary>ブラウザでのユーザー認証待ち</summary>
    WaitingForBrowser,
    /// <summary>CreateToken API ポーリング中</summary>
    Polling,
    /// <summary>アカウント選択中</summary>
    SelectingAccount,
    /// <summary>ロール選択中</summary>
    SelectingRole,
    /// <summary>認証完了</summary>
    Authenticated,
    /// <summary>エラー発生</summary>
    Error
}

/// <summary>
/// SSO で利用可能なアカウント情報
/// </summary>
public class SSOAccountInfo
{
    /// <summary>AWS アカウント ID</summary>
    public string AccountId { get; set; } = "";

    /// <summary>アカウント名</summary>
    public string AccountName { get; set; } = "";

    /// <summary>UI 表示用の名前（形式: "アカウント名 (アカウントID)"）</summary>
    public string DisplayName => $"{AccountName} ({AccountId})";
}

/// <summary>
/// SSO で取得した一時的な AWS 認証情報
/// </summary>
public class SSOTemporaryCredentials
{
    /// <summary>AWS Access Key ID</summary>
    public string AccessKeyId { get; set; } = "";

    /// <summary>AWS Secret Access Key</summary>
    public string SecretAccessKey { get; set; } = "";

    /// <summary>セッショントークン</summary>
    public string SessionToken { get; set; } = "";

    /// <summary>有効期限</summary>
    public DateTime Expiration { get; set; }
}


/// <summary>
/// SSO セッション情報のファイルキャッシュ用モデル
/// </summary>
public class SSOCachedSession
{
    public string AccessKeyId { get; set; } = "";
    public string SecretAccessKey { get; set; } = "";
    public string SessionToken { get; set; } = "";
    public DateTime Expiration { get; set; }
    public string? AccessToken { get; set; }
    public DateTime? AccessTokenExpiry { get; set; }
    public string? SsoRegion { get; set; }
}
