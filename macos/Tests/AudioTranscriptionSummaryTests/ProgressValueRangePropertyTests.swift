// ProgressValueRangePropertyTests.swift
// Feature: amazon-transcribe-integration, Property 3: 進捗値の範囲整合性
// モックの TranscribeClient を使用し、任意の文字起こし処理で onProgress の値が 0.0〜1.0 の範囲内であることを検証する
// **Validates: Requirements 2.5**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック AWSCredentialManager（認証情報を常に返す）

/// 有効な認証情報を常に返すモック
/// 進捗値テストでは認証情報の検証を通過させる必要があるため使用する
private final class MockCredentialManagerForProgress: AWSCredentialManaging, @unchecked Sendable {
    func loadCredentials() -> AWSCredentials? {
        AWSCredentials(accessKeyId: "testKey", secretAccessKey: "testSecret", region: "ap-northeast-1")
    }
    func saveCredentials(_ credentials: AWSCredentials) throws {}
    func deleteCredentials() throws {}
    var hasCredentials: Bool { true }
}

// MARK: - モック S3Client（アップロード・削除を記録）

/// S3 操作を成功させるモック
/// 実際の S3 通信を行わず、putObject / deleteObject を即座に成功させる
private final class MockS3ClientForProgress: S3ClientProtocol, @unchecked Sendable {
    func putObject(bucket: String, key: String, fileURL: URL) async throws {}
    func deleteObject(bucket: String, key: String) async throws {}
}

// MARK: - モック TranscribeClient（即座に完了を返す）

/// Transcribe ジョブを即座に完了させるモック
/// ポーリング回数を制御して進捗通知の検証を可能にする
private final class MockTranscribeClientForProgress: TranscribeClientProtocol, @unchecked Sendable {
    /// ポーリング時に inProgress を返す回数
    private let pollCount: Int
    /// 完了時に返すテキスト
    private let resultText: String
    /// 現在のポーリング回数
    private var currentPoll = 0

    init(pollCount: Int = 2, resultText: String = "テスト文字起こし結果") {
        self.pollCount = pollCount
        self.resultText = resultText
    }

    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String {
        return "test-job-\(UUID().uuidString)"
    }

    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus {
        currentPoll += 1
        if currentPoll > pollCount {
            return .completed(transcriptText: resultText)
        }
        return .inProgress
    }
}

// MARK: - Property 3: 進捗値の範囲整合性（Progress Value Range Consistency）

final class ProgressValueRangePropertyTests: XCTestCase {

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

    /// ランダムなポーリング回数を生成するジェネレータ（0〜5回）
    private var pollCountGen: Gen<Int> {
        Gen<Int>.fromElements(in: 0...5)
    }

    // MARK: - プロパティテスト

    /// 任意の文字起こし処理において、onProgress で通知されるすべての進捗値が
    /// 0.0 以上 1.0 以下の範囲内であることを検証する
    func testProgressValuesAreWithinRange() {
        property("進捗値の範囲整合性: すべての onProgress 値が 0.0〜1.0 の範囲内")
            <- forAll(self.fileNameGen, self.extensionGen, self.languageGen, self.pollCountGen) {
                (fileName: String, ext: String, language: TranscriptionLanguage, pollCount: Int) in

                // 進捗値を記録する配列（スレッドセーフ）
                let progressValues = LockedArray<Double>()

                // モックを使用して TranscribeClient を構築
                let credentialManager = MockCredentialManagerForProgress()
                let s3Client = MockS3ClientForProgress()
                let transcribeClient = MockTranscribeClientForProgress(pollCount: pollCount)

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

                let audioFile = AudioFile(
                    id: UUID(),
                    url: fileURL,
                    fileName: fileName,
                    fileExtension: ext,
                    duration: 10.0,
                    fileSize: 1024,
                    createdAt: Date()
                )

                // 同期的に非同期処理を実行
                let expectation = XCTestExpectation(description: "transcribe")
                var allInRange = true

                Task {
                    do {
                        _ = try await client.transcribe(
                            audioFile: audioFile,
                            language: language,
                            onProgress: { value in
                                progressValues.append(value)
                            }
                        )
                    } catch {
                        // エラーは無視（進捗値の範囲のみ検証）
                    }
                    expectation.fulfill()
                }

                // 完了を待機
                let waiter = XCTWaiter()
                let result = waiter.wait(for: [expectation], timeout: 10.0)

                guard result == .completed else { return false }

                // すべての進捗値が 0.0〜1.0 の範囲内であることを検証
                let values = progressValues.getAll()
                guard !values.isEmpty else { return false }

                for value in values {
                    if value < 0.0 || value > 1.0 {
                        allInRange = false
                        break
                    }
                }

                return allInRange
            }
    }
}

// MARK: - スレッドセーフな配列

/// onProgress コールバックからスレッドセーフに値を記録するためのラッパー
private final class LockedArray<T>: @unchecked Sendable {
    private var array: [T] = []
    private let lock = NSLock()

    func append(_ value: T) {
        lock.lock()
        array.append(value)
        lock.unlock()
    }

    func getAll() -> [T] {
        lock.lock()
        let copy = array
        lock.unlock()
        return copy
    }
}
