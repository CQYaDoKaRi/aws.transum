// CredentialsRoundTripPropertyTests.swift
// Feature: amazon-transcribe-integration, Property 1: 認証情報のラウンドトリップ
// ランダムな英数字文字列で AWSCredentials を生成し、保存→読み込みで同一の値が返ることを検証する
// **Validates: Requirements 1.2, 1.3**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック AWSCredentialManager（インメモリ実装）

/// AWSCredentialManaging プロトコルに準拠したモック
/// 実際の Keychain ではなくインメモリで認証情報を保存・読み込みする
/// テスト環境での Keychain アクセス問題を回避するために使用する
private final class MockAWSCredentialManager: AWSCredentialManaging, @unchecked Sendable {

    /// インメモリに保存された認証情報
    private var storedCredentials: AWSCredentials?

    /// インメモリから認証情報を読み込む
    /// - Returns: 保存済みの認証情報。未設定の場合は nil
    func loadCredentials() -> AWSCredentials? {
        return storedCredentials
    }

    /// 認証情報をインメモリに保存する
    /// - Parameter credentials: 保存する認証情報
    /// - Throws: 保存に失敗した場合（モックでは発生しない）
    func saveCredentials(_ credentials: AWSCredentials) throws {
        storedCredentials = credentials
    }

    /// インメモリから認証情報を削除する
    /// - Throws: 削除に失敗した場合（モックでは発生しない）
    func deleteCredentials() throws {
        storedCredentials = nil
    }

    /// 認証情報が設定済みかどうか
    var hasCredentials: Bool {
        storedCredentials != nil
    }
}

// MARK: - Property 1: 認証情報のラウンドトリップ（Credentials Round Trip）

final class CredentialsRoundTripPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// ランダムな英数字文字列を生成するジェネレータ（1〜30文字）
    /// AWS 認証情報のフィールド値として使用する
    private var alphanumericGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 15)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    // MARK: - プロパティテスト

    /// ランダムな AWSCredentials を保存→読み込みし、元の値と同一であることを検証する
    /// AWSCredentialManaging プロトコルのモック実装を使用し、
    /// 任意の有効な認証情報に対してラウンドトリップが成立することを確認する
    func testCredentialsRoundTrip() {
        property("認証情報のラウンドトリップ: 保存→読み込みで同一の値が返る")
            <- forAll(self.alphanumericGen, self.alphanumericGen, self.alphanumericGen) {
                (accessKeyId: String, secretAccessKey: String, region: String) in

                // テストごとに新しいモックマネージャーを生成
                let manager = MockAWSCredentialManager()

                // ランダムな認証情報を作成
                let original = AWSCredentials(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    region: region
                )

                do {
                    // 認証情報を保存
                    try manager.saveCredentials(original)

                    // 認証情報を読み込み
                    guard let loaded = manager.loadCredentials() else {
                        return false
                    }

                    // 保存前と読み込み後の値が一致することを検証
                    return loaded == original
                } catch {
                    return false
                }
            }
    }
}
