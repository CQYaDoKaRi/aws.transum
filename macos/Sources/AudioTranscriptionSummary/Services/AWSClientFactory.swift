// AWSClientFactory.swift
// 認証方式に応じた AWS SDK credential resolver の生成を一元管理するファクトリ
// accessKey 方式と awsProfile 方式の分岐をここに集約する

import Foundation
import SmithyIdentity

// MARK: - AWSClientFactory

/// 現在の認証設定に基づいて AWS SDK の credential resolver を生成するファクトリ
/// `authMethod` に応じて StaticAWSCredentialIdentityResolver または
/// AWSProfileCredentialHelper 経由で resolver を生成する
struct AWSClientFactory {

    // MARK: - Credential Resolver 生成

    /// 現在の認証設定に基づいて credential resolver を生成する
    ///
    /// - `accessKey`: settings.json の Access Key ID / Secret Access Key から StaticAWSCredentialIdentityResolver を生成
    /// - `awsProfile`: ~/.aws/credentials または ~/.aws/config からプロファイルの認証情報を読み取り、StaticAWSCredentialIdentityResolver を生成
    ///   SSO プロファイル等で静的キーがない場合は AWS_PROFILE 環境変数を設定して nil を返す
    ///
    /// - Returns: credential resolver。SSO プロファイル等で SDK デフォルトに委譲する場合は nil
    /// - Throws: 認証情報が無効な場合
    static func makeCredentialResolver() throws -> StaticAWSCredentialIdentityResolver? {
        let settings = AppSettingsStore().load()
        let authMethod = AuthMethod(rawValue: settings.authMethod) ?? .accessKey

        switch authMethod {
        case .accessKey:
            // 従来の Access Key 方式
            let accessKey = settings.accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
            let secretKey = settings.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !accessKey.isEmpty, !secretKey.isEmpty else {
                throw AWSClientFactoryError.missingCredentials
            }

            let identity = AWSCredentialIdentity(
                accessKey: accessKey,
                secret: secretKey
            )
            return StaticAWSCredentialIdentityResolver(identity)

        case .awsProfile:
            // AWS Profile 方式
            let profileName = settings.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profileName.isEmpty else {
                throw AWSClientFactoryError.noProfileSelected
            }

            do {
                let creds = try AWSProfileCredentialHelper.resolveCredentials(profileName: profileName)
                let identity = AWSCredentialIdentity(
                    accessKey: creds.accessKey,
                    secret: creds.secretKey,
                    sessionToken: creds.sessionToken
                )
                return StaticAWSCredentialIdentityResolver(identity)
            } catch AWSProfileCredentialHelper.ProfileCredentialError.noStaticCredentials {
                // SSO プロファイル等: AWS_PROFILE 環境変数が設定済み、SDK デフォルトに委譲
                return nil
            }
        }
    }

    // MARK: - リージョン解決

    /// 現在の認証設定に基づいてリージョンを解決する
    ///
    /// - `awsProfile`: プロファイルの region を優先、未設定時は settings.json にフォールバック
    /// - `accessKey`: settings.json のリージョンを使用
    ///
    /// - Returns: リージョン文字列
    static func currentRegion() -> String {
        let settings = AppSettingsStore().load()
        let authMethod = AuthMethod(rawValue: settings.authMethod) ?? .accessKey

        if authMethod == .awsProfile {
            let profileName = settings.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profileName.isEmpty,
               let profileRegion = AWSProfileCredentialHelper.resolveRegion(profileName: profileName),
               !profileRegion.isEmpty {
                return profileRegion
            }
        }

        // フォールバック: settings.json のリージョン
        return settings.region
    }

    // MARK: - エラー型

    /// AWSClientFactory のエラー
    enum AWSClientFactoryError: LocalizedError {
        /// Access Key が未設定
        case missingCredentials
        /// プロファイルが未選択
        case noProfileSelected

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "AWS 認証情報が設定されていません。設定画面から認証情報を入力してください。"
            case .noProfileSelected:
                return "AWS プロファイルが選択されていません。設定画面からプロファイルを選択してください。"
            }
        }
    }
}
