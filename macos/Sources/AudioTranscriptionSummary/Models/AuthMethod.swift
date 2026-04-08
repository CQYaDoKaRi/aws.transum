// AuthMethod.swift
// AWS 認証方式を表す列挙型

import Foundation

// MARK: - AuthMethod（認証方式）

/// AWS 認証方式を表す列挙型
/// - `accessKey`: Access Key ID / Secret Access Key による手動入力方式
/// - `awsProfile`: AWS CLI プロファイル選択方式（SSO / AssumeRole 対応）
/// - `sso`: IAM Identity Center（SSO）方式
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case sso = "sso"
    case awsProfile = "awsProfile"
    case accessKey = "accessKey"

    /// Identifiable 準拠用の ID
    var id: String { rawValue }

    /// UI 表示用の名前
    var displayName: String {
        switch self {
        case .accessKey:
            return "Access Key"
        case .awsProfile:
            return "AWS Profile"
        case .sso:
            return "IAM Identity Center"
        }
    }
}
