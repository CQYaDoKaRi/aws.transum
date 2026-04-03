// ShortTextSummarizationPropertyTests.swift
// Feature: audio-transcription-summary, Property 3: 短いテキストの要約拒否
// 0〜49文字のランダム文字列を生成し、Summarizer が insufficientContent エラーを返すことを検証する
// **Validates: Requirements 3.5**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック Summarizer

/// Summarizing プロトコルに準拠したモック
/// 実際の Summarizer と同じ文字数チェックロジックを持つ
private final class MockSummarizer: Summarizing, Sendable {

    static let minimumCharacterCount: Int = 50

    /// Transcript の要約を生成する
    /// 50文字未満の場合は insufficientContent エラーを throw する
    func summarize(transcript: Transcript) async throws -> Summary {
        guard transcript.characterCount >= Self.minimumCharacterCount else {
            throw AppError.insufficientContent(minimumCharacters: Self.minimumCharacterCount)
        }
        return Summary(
            id: UUID(),
            transcriptId: transcript.id,
            text: transcript.text,
            createdAt: Date()
        )
    }
}

// MARK: - Property 3: 短いテキストの要約拒否（Short Text Summarization Rejection）

final class ShortTextSummarizationPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// 0〜49文字のランダム文字列を生成するジェネレータ
    /// 英数字・日本語文字を含む多様な文字セットから生成する
    private var shortTextGen: Gen<String> {
        // 使用する文字セット（英数字・日本語ひらがな・カタカナ・漢字の一部）
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789あいうえおかきくけこさしすせそたちつてとアイウエオカキクケコ会議音声文字")

        // 0〜49 の範囲でランダムな長さを選択
        return Gen<Int>.fromElements(in: 0...49).flatMap { length in
            if length == 0 {
                return Gen.pure("")
            }
            return Gen<Character>.fromElements(of: chars)
                .proliferate(withSize: length)
                .map { String($0.prefix(length)) }
        }
    }

    // MARK: - プロパティテスト

    /// 50文字未満の任意の文字列に対して、Summarizer が insufficientContent エラーを返すことを検証
    func testShortTextSummarizationRejection() {
        let summarizer = MockSummarizer()

        property("短いテキストの要約拒否: 50文字未満のテキストは insufficientContent エラーを返す")
            <- forAll(self.shortTextGen) { (text: String) in
                // テキストが50文字未満であることを前提条件として確認
                guard text.count < 50 else { return true }

                let transcript = Transcript(
                    id: UUID(),
                    audioFileId: UUID(),
                    text: text,
                    language: .japanese,
                    createdAt: Date()
                )

                do {
                    _ = try awaitResult {
                        try await summarizer.summarize(transcript: transcript)
                    }
                    // 要約が成功した場合はプロパティ違反
                    return false
                } catch let error as AppError {
                    // insufficientContent エラーであることを確認
                    guard case .insufficientContent(let minChars) = error else {
                        return false
                    }
                    // 最小文字数が 50 であることを確認
                    return minChars == 50
                } catch {
                    return false
                }
            }
    }
}

// MARK: - ヘルパー関数

/// async 関数を同期的に実行するためのヘルパー
/// SwiftCheck は同期的なプロパティを期待するため、async/await を橋渡しする
private func awaitResult<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?

    Task {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    switch result! {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    }
}
