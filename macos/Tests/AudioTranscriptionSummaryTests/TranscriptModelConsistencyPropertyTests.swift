// TranscriptModelConsistencyPropertyTests.swift
// Feature: amazon-transcribe-integration, Property 4: Transcript モデルの整合性
// モックを使用し、成功した文字起こしの Transcript が正しい audioFileId、language、非空テキストを持つことを検証する
// **Validates: Requirements 2.6**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック AWSCredentialManager（認証情報を常に返す）

/// 有効な認証情報を常に返すモック
private final class MockCredentialManagerForTranscript: AWSCredentialManaging, @unchecked Sendable {
    func loadCredentials() -> AWSCredentials? {
        AWSCredentials(accessKeyId: "testKey", secretAccessKey: "testSecret", region: "ap-northeast-1")
    }
    func saveCredentials(_ credentials: AWSCredentials) throws {}
    func deleteCredentials() throws {}
    var hasCredentials: Bool { true }
}

// MARK: - モック S3Client（操作を即座に成功させる）

/// S3 操作を成功させるモック
private final class MockS3ClientForTranscript: S3ClientProtocol, @unchecked Sendable {
    func putObject(bucket: String, key: String, fileURL: URL) async throws {}
    func deleteObject(bucket: String, key: String) async throws {}
}

// MARK: - モック TranscribeClientProtocol（指定テキストで即座に完了）

/// 指定されたテキストで即座に完了を返すモック
private final class MockTranscribeClientForTranscript: TranscribeClientProtocol, @unchecked Sendable {
    private let resultText: String

    init(resultText: String) {
        self.resultText = resultText
    }

    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String {
        return "test-job-\(UUID().uuidString)"
    }

    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus {
        return .completed(transcriptText: resultText)
    }
}

// MARK: - Property 4: Transcript モデルの整合性（Transcript Model Consistency）

final class TranscriptModelConsistencyPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// ランダムなファイル名を生成するジェネレータ
    private var fileNameGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 10)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    /// ランダムなファイル拡張子を生成するジェネレータ
    private var extensionGen: Gen<String> {
        Gen<String>.fromElements(of: ["m4a", "wav", "mp3"])
    }

    /// ランダムな TranscriptionLanguage を生成するジェネレータ
    private var languageGen: Gen<TranscriptionLanguage> {
        Gen<TranscriptionLanguage>.fromElements(of: [.japanese, .english])
    }

    /// ランダムな非空テキストを生成するジェネレータ（文字起こし結果として使用）
    private var transcriptTextGen: Gen<String> {
        let chars = Array("あいうえおかきくけこabcdefghijklmnopqrstuvwxyz0123456789 ")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 20)
            .map { String($0) }
            .suchThat { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - プロパティテスト

    /// 成功した文字起こし処理において、返却される Transcript の
    /// audioFileId が入力 AudioFile の id と一致し、language が指定言語と一致し、text が空でないことを検証する
    func testTranscriptModelConsistency() {
        property("Transcript モデルの整合性: audioFileId、language、text が正しい")
            <- forAll(self.fileNameGen, self.extensionGen, self.languageGen, self.transcriptTextGen) {
                (fileName: String, ext: String, language: TranscriptionLanguage, resultText: String) in

                // モックを使用して TranscribeClient を構築
                let credentialManager = MockCredentialManagerForTranscript()
                let s3Client = MockS3ClientForTranscript()
                let transcribeClient = MockTranscribeClientForTranscript(resultText: resultText)

                let client = TranscribeClient(
                    credentialManager: credentialManager,
                    s3BucketName: "test-bucket",
                    s3Client: s3Client,
                    transcribeClient: transcribeClient,
                    pollingInterval: 1_000_000 // 1ms（テスト高速化）
                )

                // テスト用の AudioFile を作成
                let tempDir = FileManager.default.temporaryDirectory
                let fileURL = tempDir.appendingPathComponent("\(fileName).\(ext)")
                FileManager.default.createFile(atPath: fileURL.path, contents: Data("test".utf8))
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let audioFileId = UUID()
                let audioFile = AudioFile(
                    id: audioFileId,
                    url: fileURL,
                    fileName: fileName,
                    fileExtension: ext,
                    duration: 10.0,
                    fileSize: 1024,
                    createdAt: Date()
                )

                // 同期的に非同期処理を実行
                let expectation = XCTestExpectation(description: "transcribe")
                var transcript: Transcript?

                Task {
                    do {
                        transcript = try await client.transcribe(
                            audioFile: audioFile,
                            language: language,
                            onProgress: { _ in }
                        )
                    } catch {
                        // エラー時は transcript が nil のまま
                    }
                    expectation.fulfill()
                }

                // 完了を待機
                let waiter = XCTWaiter()
                let waitResult = waiter.wait(for: [expectation], timeout: 10.0)

                guard waitResult == .completed, let result = transcript else { return false }

                // audioFileId が入力と一致することを検証
                let idMatches = result.audioFileId == audioFileId

                // language が指定言語と一致することを検証
                let languageMatches = result.language == language

                // text が空でないことを検証
                let textNonEmpty = !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                return idMatches && languageMatches && textNonEmpty
            }
    }
}
