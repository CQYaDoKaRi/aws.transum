// AWSCredentials.swift
// AWS 認証情報のデータモデル定義

import Foundation

// MARK: - AWSCredentials（AWS 認証情報）

/// AWS 認証情報を保持する構造体
/// Keychain に保存・読み込みされる認証情報のデータモデル
struct AWSCredentials: Equatable, Sendable {
    /// AWS Access Key ID
    let accessKeyId: String
    /// AWS Secret Access Key
    let secretAccessKey: String
    /// AWS リージョン（例: "ap-northeast-1"）
    let region: String

    /// 認証情報が有効か（各フィールドが空白のみでないか）を判定する
    var isValid: Bool {
        !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
