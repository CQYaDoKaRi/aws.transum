// AWSProfileCredentialHelper.swift
// AWS CLI プロファイルから認証情報を解決するヘルパー
// ~/.aws/credentials と ~/.aws/config から access_key / secret_key / session_token を読み取る

import Foundation

// MARK: - AWSProfileCredentialHelper

/// AWS CLI プロファイルから認証情報を解決するユーティリティ
/// 1. ~/.aws/credentials および ~/.aws/config から静的キーを直接読み取り
/// 2. 静的キーが存在しない場合（SSO プロファイル等）は AWS_PROFILE 環境変数を設定して SDK デフォルトに委譲
struct AWSProfileCredentialHelper {

    /// 認証情報の解決結果
    struct ResolvedCredentials {
        let accessKey: String
        let secretKey: String
        let sessionToken: String?
        let region: String?
    }

    // MARK: - デフォルトパス

    /// ~/.aws/credentials のデフォルトパス
    static var defaultCredentialsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aws/credentials"
    }

    /// ~/.aws/config のデフォルトパス
    static var defaultConfigPath: String {
        AWSConfigParser.defaultConfigPath
    }

    // MARK: - 認証情報の解決

    /// プロファイルから認証情報を解決する
    ///
    /// 解決順序:
    /// 1. ~/.aws/credentials の該当プロファイルセクションから access_key / secret_key を読み取り
    /// 2. 見つからない場合は ~/.aws/config の該当プロファイルセクションから読み取り
    /// 3. どちらにも静的キーがない場合（SSO プロファイル等）は AWS_PROFILE 環境変数を設定
    ///
    /// - Parameter profileName: 解決するプロファイル名
    /// - Returns: 解決された認証情報
    /// - Throws: 認証情報が見つからない場合
    static func resolveCredentials(profileName: String) throws -> ResolvedCredentials {
        // 1. credentials ファイルから読み取り
        if let creds = readCredentialsFromFile(
            path: defaultCredentialsPath,
            profileName: profileName,
            isConfigFile: false
        ) {
            return creds
        }

        // 2. config ファイルから読み取り
        if let creds = readCredentialsFromFile(
            path: defaultConfigPath,
            profileName: profileName,
            isConfigFile: true
        ) {
            return creds
        }

        // 3. SSO プロファイル等: AWS_PROFILE 環境変数を設定して SDK デフォルトに委譲
        setenv("AWS_PROFILE", profileName, 1)

        // region だけは config から読み取れる可能性がある
        let region = resolveRegion(profileName: profileName)

        throw ProfileCredentialError.noStaticCredentials(
            profileName: profileName,
            region: region
        )
    }

    // MARK: - リージョンの解決

    /// プロファイルの region 設定を読み取る
    ///
    /// - Parameter profileName: プロファイル名
    /// - Returns: region 文字列。未設定の場合は nil
    static func resolveRegion(profileName: String) -> String? {
        // config ファイルからリージョンを読み取り
        let configPath = defaultConfigPath
        guard FileManager.default.fileExists(atPath: configPath),
              let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }

        return parseValue(
            from: content,
            profileName: profileName,
            key: "region",
            isConfigFile: true
        )
    }

    // MARK: - INI ファイル解析（プライベート）

    /// INI ファイルから指定プロファイルの認証情報を読み取る
    private static func readCredentialsFromFile(
        path: String,
        profileName: String,
        isConfigFile: Bool
    ) -> ResolvedCredentials? {
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let accessKey = parseValue(from: content, profileName: profileName, key: "aws_access_key_id", isConfigFile: isConfigFile)
        let secretKey = parseValue(from: content, profileName: profileName, key: "aws_secret_access_key", isConfigFile: isConfigFile)

        guard let ak = accessKey, let sk = secretKey,
              !ak.isEmpty, !sk.isEmpty else {
            return nil
        }

        let sessionToken = parseValue(from: content, profileName: profileName, key: "aws_session_token", isConfigFile: isConfigFile)
        let region = parseValue(from: content, profileName: profileName, key: "region", isConfigFile: isConfigFile)

        return ResolvedCredentials(
            accessKey: ak,
            secretKey: sk,
            sessionToken: sessionToken,
            region: region
        )
    }

    /// INI ファイルから指定プロファイル・キーの値を取得する
    ///
    /// - Parameters:
    ///   - content: ファイル内容
    ///   - profileName: プロファイル名
    ///   - key: 取得するキー名
    ///   - isConfigFile: config ファイルの場合は true（セクション名が `[profile xxx]` 形式）
    /// - Returns: 値文字列。見つからない場合は nil
    static func parseValue(
        from content: String,
        profileName: String,
        key: String,
        isConfigFile: Bool
    ) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var inTargetSection = false

        // 対象セクションヘッダーを構築
        let targetHeaders: [String]
        if profileName == "default" {
            // default プロファイルは [default] で統一
            targetHeaders = ["[default]"]
        } else if isConfigFile {
            // config ファイルでは [profile xxx] 形式
            targetHeaders = ["[profile \(profileName)]"]
        } else {
            // credentials ファイルでは [xxx] 形式
            targetHeaders = ["[\(profileName)]"]
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行・コメント行をスキップ
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix(";") {
                continue
            }

            // セクションヘッダーの検出
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionName = trimmed.trimmingCharacters(in: .whitespaces)
                inTargetSection = targetHeaders.contains(sectionName)
                continue
            }

            // 対象セクション内のキーバリューペアを検索
            if inTargetSection {
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let k = parts[0].trimmingCharacters(in: .whitespaces)
                    let v = parts[1].trimmingCharacters(in: .whitespaces)
                    if k == key {
                        return v
                    }
                }
            }
        }

        return nil
    }

    // MARK: - エラー型

    /// プロファイル認証情報解決のエラー
    enum ProfileCredentialError: LocalizedError {
        /// 静的認証情報が見つからない（SSO プロファイル等）
        case noStaticCredentials(profileName: String, region: String?)

        var errorDescription: String? {
            switch self {
            case .noStaticCredentials(let profileName, _):
                return "プロファイル「\(profileName)」に静的認証情報が見つかりません。AWS_PROFILE 環境変数を設定しました。"
            }
        }
    }
}
