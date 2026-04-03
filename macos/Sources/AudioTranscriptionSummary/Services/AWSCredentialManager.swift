// AWSCredentialManager.swift
// macOS Keychain を使用した AWS 認証情報の安全な保存・読み込み・削除

import Foundation
import Security

// MARK: - AWSCredentialManager（AWS 認証情報マネージャー）

/// macOS Keychain を使用して AWS 認証情報を安全に管理するクラス
/// 平文でのファイルシステム保存は行わず、OS レベルの暗号化ストレージを使用する
final class AWSCredentialManager: AWSCredentialManaging, Sendable {

    // MARK: - 定数

    /// Keychain サービス名
    private let serviceName = "com.app.AudioTranscriptionSummary.aws"

    /// Keychain に保存する各フィールドのアカウントキー
    private enum AccountKey {
        static let accessKeyId = "accessKeyId"
        static let secretAccessKey = "secretAccessKey"
        static let region = "region"
    }

    // MARK: - AWSCredentialManaging 準拠

    /// Keychain から認証情報を読み込む
    /// - Returns: 保存済みの認証情報。未設定または一部欠損の場合は nil
    func loadCredentials() -> AWSCredentials? {
        guard
            let accessKeyId = loadItem(account: AccountKey.accessKeyId),
            let secretAccessKey = loadItem(account: AccountKey.secretAccessKey),
            let region = loadItem(account: AccountKey.region)
        else {
            return nil
        }

        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            region: region
        )
    }

    /// 認証情報を Keychain に保存する
    /// 既存のアイテムがある場合は上書きする
    /// - Parameter credentials: 保存する認証情報
    /// - Throws: Keychain 操作に失敗した場合
    func saveCredentials(_ credentials: AWSCredentials) throws {
        try saveItem(account: AccountKey.accessKeyId, value: credentials.accessKeyId)
        try saveItem(account: AccountKey.secretAccessKey, value: credentials.secretAccessKey)
        try saveItem(account: AccountKey.region, value: credentials.region)
    }

    /// Keychain から認証情報を完全に削除する
    /// - Throws: Keychain 操作に失敗した場合
    func deleteCredentials() throws {
        try deleteItem(account: AccountKey.accessKeyId)
        try deleteItem(account: AccountKey.secretAccessKey)
        try deleteItem(account: AccountKey.region)
    }

    /// 認証情報が設定済みかどうか
    var hasCredentials: Bool {
        loadCredentials() != nil
    }

    // MARK: - Keychain 操作（プライベート）

    /// Keychain からアイテムを読み込む
    /// - Parameter account: アカウントキー（フィールド識別子）
    /// - Returns: 保存された文字列値。未設定の場合は nil
    private func loadItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Keychain にアイテムを保存する（既存アイテムがあれば更新）
    /// - Parameters:
    ///   - account: アカウントキー（フィールド識別子）
    ///   - value: 保存する文字列値
    /// - Throws: Keychain 操作に失敗した場合
    private func saveItem(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // 既存アイテムの削除を試みる（エラーは無視）
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // 新規アイテムを追加
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Keychain からアイテムを削除する
    /// - Parameter account: アカウントキー（フィールド識別子）
    /// - Throws: Keychain 操作に失敗した場合（アイテム未存在は許容）
    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound はアイテムが存在しない場合なので許容する
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
}

// MARK: - KeychainError（Keychain エラー）

/// Keychain 操作に関するエラー
enum KeychainError: LocalizedError {
    /// 文字列の Data 変換に失敗
    case encodingFailed
    /// Keychain への保存に失敗
    case saveFailed(status: OSStatus)
    /// Keychain からの削除に失敗
    case deleteFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "認証情報のエンコードに失敗しました"
        case .saveFailed(let status):
            return "Keychain への保存に失敗しました（ステータス: \(status)）"
        case .deleteFailed(let status):
            return "Keychain からの削除に失敗しました（ステータス: \(status)）"
        }
    }
}
