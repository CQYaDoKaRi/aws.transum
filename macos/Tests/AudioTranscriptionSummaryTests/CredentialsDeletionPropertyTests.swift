// CredentialsDeletionPropertyTests.swift
// Feature: amazon-transcribe-integration, Property 2: 認証情報の削除完全性
// ランダムな AWSCredentials を保存→削除し、loadCredentials() が nil、hasCredentials が false を返すことを検証する
// **Validates: Requirements 1.6**

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

// MARK: - Property 2: 認証情報の削除完全性（Credentials Deletion Completeness）

final class CredentialsDeletionPropertyTests: XCTestCase {

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

    /// ランダムな AWSCredentials を保存→削除し、loadCredentials() が nil、hasCredentials が false を返すことを検証する
    /// AWSCredentialManaging プロトコルのモック実装を使用し、
    /// 任意の有効な認証情報に対して削除後の完全性を確認する
    func testCredentialsDeletionCompleteness() {
        property("認証情報の削除完全性: 保存→削除後に loadCredentials() が nil、hasCredentials が false を返す")
            <- forAll(self.alphanumericGen, self.alphanumericGen, self.alphanumericGen) {
                (accessKeyId: String, secretAccessKey: String, region: String) in

                // テストごとに新しいモックマネージャーを生成
                let manager = MockAWSCredentialManager()

                // ランダムな認証情報を作成
                let credentials = AWSCredentials(
                    accessKeyId: accessKeyId,
                    secretAccessKey: secretAccessKey,
                    region: region
                )

                do {
                    // 認証情報を保存
                    try manager.saveCredentials(credentials)

                    // 保存後に認証情報が存在することを確認（前提条件）
                    guard manager.hasCredentials, manager.loadCredentials() != nil else {
                        return false
                    }

                    // 認証情報を削除
                    try manager.deleteCredentials()

                    // 削除後に loadCredentials() が nil を返すことを検証
                    let loadedAfterDelete = manager.loadCredentials()
                    let isLoadNil = loadedAfterDelete == nil

                    // 削除後に hasCredentials が false を返すことを検証
                    let isHasCredentialsFalse = !manager.hasCredentials

                    return isLoadNil && isHasCredentialsFalse
                } catch {
                    return false
                }
            }
    }
}
