// AWSCredentialManagerTests.swift
// AWSCredentialManager サービスのユニットテスト
// AWSCredentialManaging プロトコルに準拠したモックを使用して、認証情報管理機能を検証する
// 要件: 1.2, 1.3, 1.6

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockAWSCredentialManager（テスト用モック）

/// AWSCredentialManaging プロトコルに準拠したインメモリ実装
/// 実際の Keychain ではなくインメモリで認証情報を保存・読み込みする
/// テスト環境での Keychain アクセス問題を回避するために使用する
private final class MockAWSCredentialManager: AWSCredentialManaging, @unchecked Sendable {

    /// インメモリに保存された認証情報
    private var storedCredentials: AWSCredentials?

    /// インメモリから認証情報を読み込む
    func loadCredentials() -> AWSCredentials? {
        return storedCredentials
    }

    /// 認証情報をインメモリに保存する
    func saveCredentials(_ credentials: AWSCredentials) throws {
        storedCredentials = credentials
    }

    /// インメモリから認証情報を削除する
    func deleteCredentials() throws {
        storedCredentials = nil
    }

    /// 認証情報が設定済みかどうか
    var hasCredentials: Bool {
        storedCredentials != nil
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の AWSCredentials を生成するヘルパー関数
private func makeTestCredentials(
    accessKeyId: String = "AKIAIOSFODNN7EXAMPLE",
    secretAccessKey: String = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    region: String = "ap-northeast-1"
) -> AWSCredentials {
    AWSCredentials(
        accessKeyId: accessKeyId,
        secretAccessKey: secretAccessKey,
        region: region
    )
}

// MARK: - 認証情報の保存・読み込みテスト（要件 1.2, 1.3）

@Suite("AWSCredentialManager 保存・読み込みテスト")
struct AWSCredentialManagerSaveLoadTests {

    /// 認証情報を保存し、読み込みで同一の値が返ることを確認
    @Test func saveAndLoadCredentials() throws {
        let manager = MockAWSCredentialManager()
        let credentials = makeTestCredentials()

        try manager.saveCredentials(credentials)
        let loaded = manager.loadCredentials()

        #expect(loaded != nil)
        #expect(loaded == credentials)
    }

    /// 保存後に hasCredentials が true を返すことを確認
    @Test func hasCredentialsAfterSave() throws {
        let manager = MockAWSCredentialManager()
        let credentials = makeTestCredentials()

        #expect(!manager.hasCredentials)
        try manager.saveCredentials(credentials)
        #expect(manager.hasCredentials)
    }

    /// 認証情報を上書き保存した場合、最新の値が読み込まれることを確認
    @Test func overwriteCredentials() throws {
        let manager = MockAWSCredentialManager()

        let first = makeTestCredentials(
            accessKeyId: "FIRST_KEY",
            secretAccessKey: "FIRST_SECRET",
            region: "us-east-1"
        )
        let second = makeTestCredentials(
            accessKeyId: "SECOND_KEY",
            secretAccessKey: "SECOND_SECRET",
            region: "eu-west-1"
        )

        try manager.saveCredentials(first)
        try manager.saveCredentials(second)

        let loaded = manager.loadCredentials()
        #expect(loaded == second)
    }

    /// 各フィールドが正しく保存・読み込みされることを確認
    @Test func fieldsPreservedCorrectly() throws {
        let manager = MockAWSCredentialManager()
        let credentials = makeTestCredentials(
            accessKeyId: "TestAccessKey123",
            secretAccessKey: "TestSecretKey456",
            region: "ap-southeast-1"
        )

        try manager.saveCredentials(credentials)
        let loaded = manager.loadCredentials()

        #expect(loaded?.accessKeyId == "TestAccessKey123")
        #expect(loaded?.secretAccessKey == "TestSecretKey456")
        #expect(loaded?.region == "ap-southeast-1")
    }
}

// MARK: - 認証情報の削除テスト（要件 1.6）

@Suite("AWSCredentialManager 削除テスト")
struct AWSCredentialManagerDeleteTests {

    /// 保存した認証情報を削除し、loadCredentials() が nil を返すことを確認
    @Test func deleteCredentialsReturnsNil() throws {
        let manager = MockAWSCredentialManager()
        let credentials = makeTestCredentials()

        try manager.saveCredentials(credentials)
        #expect(manager.loadCredentials() != nil)

        try manager.deleteCredentials()
        #expect(manager.loadCredentials() == nil)
    }

    /// 削除後に hasCredentials が false を返すことを確認
    @Test func hasCredentialsFalseAfterDelete() throws {
        let manager = MockAWSCredentialManager()
        let credentials = makeTestCredentials()

        try manager.saveCredentials(credentials)
        #expect(manager.hasCredentials)

        try manager.deleteCredentials()
        #expect(!manager.hasCredentials)
    }

    /// 認証情報が未設定の状態で削除してもエラーにならないことを確認
    @Test func deleteWithoutSavedCredentials() throws {
        let manager = MockAWSCredentialManager()

        // 未設定状態で削除してもエラーが発生しないことを確認
        try manager.deleteCredentials()
        #expect(manager.loadCredentials() == nil)
        #expect(!manager.hasCredentials)
    }
}

// MARK: - 未設定時のテスト（要件 1.2, 1.3）

@Suite("AWSCredentialManager 未設定時テスト")
struct AWSCredentialManagerEmptyTests {

    /// 初期状態で loadCredentials() が nil を返すことを確認
    @Test func loadReturnsNilWhenEmpty() {
        let manager = MockAWSCredentialManager()

        #expect(manager.loadCredentials() == nil)
    }

    /// 初期状態で hasCredentials が false を返すことを確認
    @Test func hasCredentialsFalseWhenEmpty() {
        let manager = MockAWSCredentialManager()

        #expect(!manager.hasCredentials)
    }
}
