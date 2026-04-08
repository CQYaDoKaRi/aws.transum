// SSOModels.swift
// IAM Identity Center（SSO）認証に関連するデータモデル

import Foundation

// MARK: - SSOLoginState（SSO 認証フローの状態）

/// SSO 認証フローの状態を表す列挙型
enum SSOLoginState: Equatable {
    /// 初期状態（未認証）
    case idle
    /// RegisterClient API 呼び出し中
    case registering
    /// ブラウザでのユーザー認証待ち
    case waitingForBrowser(userCode: String, verificationUri: String)
    /// CreateToken API ポーリング中
    case polling
    /// アカウント選択中
    case selectingAccount
    /// ロール選択中
    case selectingRole
    /// 認証完了
    case authenticated
    /// エラー発生
    case error(String)
}

// MARK: - SSOAccountInfo（SSO アカウント情報）

/// SSO で利用可能なアカウント情報
struct SSOAccountInfo: Identifiable, Equatable {
    /// AWS アカウント ID
    let accountId: String
    /// アカウント名
    let accountName: String

    /// Identifiable 準拠用の ID
    var id: String { accountId }

    /// UI 表示用の名前（形式: "アカウント名 (アカウントID)"）
    var displayName: String { "\(accountName) (\(accountId))" }
}

// MARK: - SSOTemporaryCredentials（SSO 一時認証情報）

/// SSO で取得した一時的な AWS 認証情報
struct SSOTemporaryCredentials: Equatable, Codable {
    /// AWS Access Key ID
    let accessKeyId: String
    /// AWS Secret Access Key
    let secretAccessKey: String
    /// セッショントークン
    let sessionToken: String
    /// 有効期限
    let expiration: Date
}


// MARK: - SSOCachedSession（SSO セッションキャッシュ）

/// SSO セッション情報のファイルキャッシュ用モデル
struct SSOCachedSession: Codable {
    /// 一時認証情報
    let credentials: SSOTemporaryCredentials
    /// SSO Access Token
    let accessToken: String?
    /// Access Token の有効期限
    let accessTokenExpiry: Date?
    /// SSO リージョン
    let ssoRegion: String?
}
