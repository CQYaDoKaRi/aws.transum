// TranscribeClientTests.swift
// TranscribeClient サービスのユニットテスト
// モック実装を使用して、エラーハンドリング、キャンセル、S3 クリーンアップ、言語コードマッピングを検証する
// 要件: 1.4, 2.7, 2.8, 3.4, 4.1, 4.2, 4.3, 4.4, 5.4

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - モック AWSCredentialManaging

/// 認証情報の返却を制御可能なモック
private final class MockCredentialManager: AWSCredentialManaging, @unchecked Sendable {
    private var storedCredentials: AWSCredentials?

    init(credentials: AWSCredentials? = nil) {
        self.storedCredentials = credentials
    }

    func loadCredentials() -> AWSCredentials? { storedCredentials }
    func saveCredentials(_ credentials: AWSCredentials) throws { storedCredentials = credentials }
    func deleteCredentials() throws { storedCredentials = nil }
    var hasCredentials: Bool { storedCredentials != nil }
}

// MARK: - モック S3ClientProtocol

/// S3 操作の成功・失敗を制御可能なモック
/// 削除呼び出しを記録して S3 クリーンアップの検証に使用する
private final class MockS3Client: S3ClientProtocol, @unchecked Sendable {
    private let putError: Error?
    private let lock = NSLock()
    private var _deleteCalledKeys: [String] = []

    /// 削除が呼ばれたキーの一覧
    var deleteCalledKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _deleteCalledKeys
    }

    init(putError: Error? = nil) {
        self.putError = putError
    }

    func putObject(bucket: String, key: String, fileURL: URL) async throws {
        if let error = putError { throw error }
    }

    func deleteObject(bucket: String, key: String) async throws {
        lock.lock()
        _deleteCalledKeys.append(key)
        lock.unlock()
    }
}

// MARK: - モック TranscribeClientProtocol

/// Transcribe ジョブの動作を制御可能なモック
private final class MockTranscribeService: TranscribeClientProtocol, @unchecked Sendable {
    private let startResult: Result<String, Error>
    private let statusSequence: [TranscriptionJobStatus]
    private let lock = NSLock()
    private var statusIndex = 0
    private var _receivedConfig: TranscribeJobConfig?

    /// 受信したジョブ設定（言語コードマッピングの検証に使用）
    var receivedConfig: TranscribeJobConfig? {
        lock.lock()
        defer { lock.unlock() }
        return _receivedConfig
    }

    init(
        startResult: Result<String, Error> = .success("test-job"),
        statusSequence: [TranscriptionJobStatus] = [.completed(transcriptText: "テスト結果")]
    ) {
        self.startResult = startResult
        self.statusSequence = statusSequence
    }

    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String {
        lock.lock()
        _receivedConfig = config
        lock.unlock()
        return try startResult.get()
    }

    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus {
        lock.lock()
        let index = min(statusIndex, statusSequence.count - 1)
        let status = statusSequence[index]
        statusIndex += 1
        lock.unlock()
        return status
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の有効な AWSCredentials を生成する
private func makeValidCredentials() -> AWSCredentials {
    AWSCredentials(accessKeyId: "AKIAIOSFODNN7EXAMPLE", secretAccessKey: "wJalrXUtnFEMI/K7MDENG", region: "ap-northeast-1")
}

/// テスト用の AudioFile を生成する（一時ファイルを作成）
private func makeTestAudioFile(ext: String = "m4a") -> (AudioFile, URL) {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("test-audio-\(UUID().uuidString).\(ext)")
    FileManager.default.createFile(atPath: fileURL.path, contents: Data("audio-data".utf8))
    let audioFile = AudioFile(
        id: UUID(),
        url: fileURL,
        fileName: "test-audio",
        fileExtension: ext,
        duration: 30.0,
        fileSize: 2048,
        createdAt: Date()
    )
    return (audioFile, fileURL)
}

/// テスト用の TranscribeClient を構築するヘルパー
private func makeClient(
    credentials: AWSCredentials? = nil,
    s3Client: MockS3Client = MockS3Client(),
    transcribeService: MockTranscribeService = MockTranscribeService()
) -> TranscribeClient {
    let credentialManager = MockCredentialManager(credentials: credentials)
    return TranscribeClient(
        credentialManager: credentialManager,
        s3BucketName: "test-bucket",
        s3Client: s3Client,
        transcribeClient: transcribeService,
        pollingInterval: 1_000_000 // 1ms（テスト高速化）
    )
}


// MARK: - 認証情報未設定時のエラーテスト（要件 1.4）

@Suite("TranscribeClient 認証情報エラーテスト")
struct TranscribeClientCredentialErrorTests {

    /// 認証情報が未設定の場合、transcriptionFailed エラーがスローされることを確認
    @Test func credentialsNotSetThrowsError() async throws {
        let client = makeClient(credentials: nil)
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }

    /// 認証情報が無効（空文字）の場合、transcriptionFailed エラーがスローされることを確認
    @Test func invalidCredentialsThrowsError() async throws {
        let invalidCredentials = AWSCredentials(accessKeyId: "  ", secretAccessKey: "", region: "ap-northeast-1")
        let client = makeClient(credentials: invalidCredentials)
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - ネットワークエラーテスト（要件 4.2）

@Suite("TranscribeClient ネットワークエラーテスト")
struct TranscribeClientNetworkErrorTests {

    /// ネットワークエラー発生時に適切な AppError がスローされることを確認
    @Test func networkErrorThrowsTranscriptionFailed() async throws {
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )
        let s3Client = MockS3Client(putError: networkError)
        let client = makeClient(credentials: makeValidCredentials(), s3Client: s3Client)
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - ジョブ失敗テスト（要件 4.3）

@Suite("TranscribeClient ジョブ失敗テスト")
struct TranscribeClientJobFailureTests {

    /// Transcribe ジョブが失敗した場合、失敗理由を含む AppError がスローされることを確認
    @Test func jobFailedThrowsTranscriptionFailed() async throws {
        let transcribeService = MockTranscribeService(
            statusSequence: [.failed(reason: "Invalid audio format")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - S3 アクセス拒否テスト（要件 4.4）

@Suite("TranscribeClient S3 アクセス拒否テスト")
struct TranscribeClientS3AccessDeniedTests {

    /// S3 アクセス拒否エラー発生時に適切な AppError がスローされることを確認
    @Test func s3AccessDeniedThrowsTranscriptionFailed() async throws {
        let accessDeniedError = NSError(
            domain: "AWSS3",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "Access Denied"]
        )
        let s3Client = MockS3Client(putError: accessDeniedError)
        let client = makeClient(credentials: makeValidCredentials(), s3Client: s3Client)
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - 無音検出テスト（要件 2.7）

@Suite("TranscribeClient 無音検出テスト")
struct TranscribeClientSilentAudioTests {

    /// 文字起こし結果が空の場合、silentAudio エラーがスローされることを確認
    @Test func silentAudioThrowsError() async throws {
        let transcribeService = MockTranscribeService(
            statusSequence: [.completed(transcriptText: "")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }

    /// 空白のみの文字起こし結果でも silentAudio エラーがスローされることを確認
    @Test func whitespaceOnlyTextThrowsSilentAudio() async throws {
        let transcribeService = MockTranscribeService(
            statusSequence: [.completed(transcriptText: "   \n  \t  ")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - キャンセルテスト（要件 2.8）

@Suite("TranscribeClient キャンセルテスト")
struct TranscribeClientCancelTests {

    /// cancel() 呼び出し後に文字起こしがエラーで終了することを確認
    @Test func cancelStopsTranscription() async throws {
        // ポーリングが長く続くように設定
        let transcribeService = MockTranscribeService(
            statusSequence: [.inProgress, .inProgress, .inProgress, .inProgress, .inProgress,
                             .completed(transcriptText: "結果")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // 少し遅延してからキャンセル
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            client.cancel()
        }

        await #expect(throws: AppError.self) {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        }
    }
}

// MARK: - S3 クリーンアップテスト（要件 3.4）

@Suite("TranscribeClient S3 クリーンアップテスト")
struct TranscribeClientS3CleanupTests {

    /// 正常完了時に S3 一時ファイルが削除されることを確認
    @Test func s3FileDeletedOnSuccess() async throws {
        let s3Client = MockS3Client()
        let transcribeService = MockTranscribeService(
            statusSequence: [.completed(transcriptText: "テスト結果テキスト")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            s3Client: s3Client,
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await client.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        // deleteObject が呼ばれたことを確認
        #expect(!s3Client.deleteCalledKeys.isEmpty)
    }

    /// エラー発生時にも S3 一時ファイルの削除が試みられることを確認
    @Test func s3FileDeletedOnError() async throws {
        let s3Client = MockS3Client()
        let transcribeService = MockTranscribeService(
            statusSequence: [.failed(reason: "テスト失敗")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            s3Client: s3Client,
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await client.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
        } catch {
            // エラーは期待通り
        }

        // エラー時にも deleteObject が呼ばれたことを確認
        #expect(!s3Client.deleteCalledKeys.isEmpty)
    }
}

// MARK: - 言語コードマッピングテスト（要件 5.4）

@Suite("TranscribeClient 言語コードマッピングテスト")
struct TranscribeClientLanguageCodeTests {

    /// 日本語（ja-JP）の言語コードが正しくマッピングされることを確認
    @Test func japaneseLanguageCodeMapping() async throws {
        let transcribeService = MockTranscribeService(
            statusSequence: [.completed(transcriptText: "日本語テスト")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await client.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        // ジョブ設定の言語コードが "ja-JP" であることを確認
        #expect(transcribeService.receivedConfig?.languageCode == "ja-JP")
    }

    /// 英語（en-US）の言語コードが正しくマッピングされることを確認
    @Test func englishLanguageCodeMapping() async throws {
        let transcribeService = MockTranscribeService(
            statusSequence: [.completed(transcriptText: "English test")]
        )
        let client = makeClient(
            credentials: makeValidCredentials(),
            transcribeService: transcribeService
        )
        let (audioFile, fileURL) = makeTestAudioFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        _ = try await client.transcribe(
            audioFile: audioFile,
            language: .english,
            onProgress: { _ in }
        )

        // ジョブ設定の言語コードが "en-US" であることを確認
        #expect(transcribeService.receivedConfig?.languageCode == "en-US")
    }
}
