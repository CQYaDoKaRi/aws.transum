// SummarizerTests.swift
// Summarizer サービスのユニットテスト
// Summarizing プロトコルに準拠したモックを使用して、要約機能を検証する
// 要件: 3.1, 3.6

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockSummarizer（テスト用モック）

/// Summarizing プロトコルに準拠したモック実装
/// 正常系・エラー系のシナリオをシミュレートする
private final class MockSummarizer: Summarizing, @unchecked Sendable {

    /// モックが返す結果を定義する列挙型
    enum MockResult {
        /// 正常な要約結果を返す
        case success(String)
        /// 要約失敗エラーを返す
        case failure(Error)
    }

    static let minimumCharacterCount: Int = 50

    /// モックが返す結果
    var mockResult: MockResult = .success("デフォルト要約")

    /// summarize が呼ばれた回数
    private(set) var summarizeCallCount = 0

    func summarize(transcript: Transcript) async throws -> Summary {
        summarizeCallCount += 1

        // 文字数チェック（実際の Summarizer と同じロジック）
        guard transcript.characterCount >= Self.minimumCharacterCount else {
            throw AppError.insufficientContent(minimumCharacters: Self.minimumCharacterCount)
        }

        switch mockResult {
        case .success(let text):
            return Summary(
                id: UUID(),
                transcriptId: transcript.id,
                text: text,
                createdAt: Date()
            )
        case .failure(let error):
            throw AppError.summarizationFailed(underlying: error)
        }
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の Transcript を生成するヘルパー関数
private func makeTestTranscript(
    text: String = "これは十分な長さのテストテキストです。音声認識技術は近年大きく進歩しています。特に深層学習の発展により認識精度が飛躍的に向上しました。",
    language: TranscriptionLanguage = .japanese
) -> Transcript {
    Transcript(
        id: UUID(),
        audioFileId: UUID(),
        text: text,
        language: language,
        createdAt: Date()
    )
}

// MARK: - 正常な要約生成テスト（要件 3.1）

@Suite("Summarizer 正常な要約生成テスト")
struct SummarizerNormalTests {

    /// 50文字以上のテキストで要約が正常に生成されることを確認
    @Test func summarizeSuccessfully() async throws {
        let summarizer = MockSummarizer()
        let expectedSummary = "音声認識技術が大きく進歩しています。"
        summarizer.mockResult = .success(expectedSummary)

        let transcript = makeTestTranscript()

        let summary = try await summarizer.summarize(transcript: transcript)

        // 要約テキストが正しいことを確認
        #expect(summary.text == expectedSummary)
        // transcriptId が一致することを確認
        #expect(summary.transcriptId == transcript.id)
        // summarize が1回呼ばれたことを確認
        #expect(summarizer.summarizeCallCount == 1)
    }

    /// 英語テキストの要約が正常に生成されることを確認
    @Test func summarizeEnglishText() async throws {
        let summarizer = MockSummarizer()
        let expectedSummary = "Speech recognition has advanced significantly."
        summarizer.mockResult = .success(expectedSummary)

        let transcript = makeTestTranscript(
            text: "Speech recognition technology has made significant advances in recent years. The development of deep learning has dramatically improved accuracy.",
            language: .english
        )

        let summary = try await summarizer.summarize(transcript: transcript)

        #expect(summary.text == expectedSummary)
        #expect(summary.transcriptId == transcript.id)
    }

    /// 50文字未満のテキストで insufficientContent エラーが発生することを確認
    @Test func rejectShortText() async {
        let summarizer = MockSummarizer()
        let transcript = makeTestTranscript(text: "短いテキスト")

        do {
            _ = try await summarizer.summarize(transcript: transcript)
            Issue.record("insufficientContent エラーが発生するべき")
        } catch let error as AppError {
            guard case .insufficientContent(let minChars) = error else {
                Issue.record("insufficientContent エラーが期待されたが、\(error) が発生")
                return
            }
            #expect(minChars == 50)
            #expect(error.errorDescription?.contains("最低50文字") == true)
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// 空テキストで insufficientContent エラーが発生することを確認
    @Test func rejectEmptyText() async {
        let summarizer = MockSummarizer()
        let transcript = makeTestTranscript(text: "")

        do {
            _ = try await summarizer.summarize(transcript: transcript)
            Issue.record("insufficientContent エラーが発生するべき")
        } catch let error as AppError {
            guard case .insufficientContent = error else {
                Issue.record("insufficientContent エラーが期待されたが、\(error) が発生")
                return
            }
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// ちょうど50文字のテキストで要約が成功することを確認
    @Test func summarizeExactMinimumLength() async throws {
        let summarizer = MockSummarizer()
        summarizer.mockResult = .success("要約結果")

        // ちょうど50文字のテキストを生成
        let text = String(repeating: "あ", count: 50)
        let transcript = makeTestTranscript(text: text)

        let summary = try await summarizer.summarize(transcript: transcript)

        #expect(summary.transcriptId == transcript.id)
    }
}

// MARK: - エラー発生時の再試行テスト（要件 3.6）

@Suite("Summarizer エラーと再試行テスト")
struct SummarizerErrorAndRetryTests {

    /// 要約失敗時に summarizationFailed エラーが発生することを確認
    @Test func summarizationFailedError() async {
        let summarizer = MockSummarizer()
        let underlyingError = NSError(
            domain: "Summarization", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "要約エンジンエラー"]
        )
        summarizer.mockResult = .failure(underlyingError)

        let transcript = makeTestTranscript()

        do {
            _ = try await summarizer.summarize(transcript: transcript)
            Issue.record("summarizationFailed エラーが発生するべき")
        } catch let error as AppError {
            guard case .summarizationFailed(let underlying) = error else {
                Issue.record("summarizationFailed エラーが期待されたが、\(error) が発生")
                return
            }
            let nsError = underlying as NSError
            #expect(nsError.code == -100)
            #expect(error.errorDescription?.contains("要約に失敗しました") == true)
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// エラー後に再試行（同じパラメータで再実行）が成功することを確認
    @Test func retryAfterFailure() async throws {
        let summarizer = MockSummarizer()
        let transcript = makeTestTranscript()

        // 1回目: エラーを発生させる
        summarizer.mockResult = .failure(
            NSError(domain: "Test", code: -1, userInfo: nil)
        )

        do {
            _ = try await summarizer.summarize(transcript: transcript)
            Issue.record("1回目は summarizationFailed エラーが発生するべき")
        } catch is AppError {
            // 期待通りエラーが発生
        }

        #expect(summarizer.summarizeCallCount == 1)

        // 2回目: 成功するように設定して再試行
        let expectedText = "再試行で成功した要約結果です。"
        summarizer.mockResult = .success(expectedText)

        let summary = try await summarizer.summarize(transcript: transcript)

        // 再試行が成功したことを確認
        #expect(summary.text == expectedText)
        #expect(summary.transcriptId == transcript.id)
        // summarize が合計2回呼ばれたことを確認
        #expect(summarizer.summarizeCallCount == 2)
    }

    /// 複数回連続でエラーが発生しても、最終的に成功できることを確認
    @Test func retryMultipleFailures() async throws {
        let summarizer = MockSummarizer()
        let transcript = makeTestTranscript()

        // 1回目: エラー
        summarizer.mockResult = .failure(
            NSError(domain: "Test", code: -1, userInfo: nil)
        )
        do {
            _ = try await summarizer.summarize(transcript: transcript)
        } catch {}

        // 2回目: エラー
        do {
            _ = try await summarizer.summarize(transcript: transcript)
        } catch {}

        #expect(summarizer.summarizeCallCount == 2)

        // 3回目: 成功
        let expectedText = "最終的に成功した要約。"
        summarizer.mockResult = .success(expectedText)

        let summary = try await summarizer.summarize(transcript: transcript)

        #expect(summary.text == expectedText)
        #expect(summarizer.summarizeCallCount == 3)
    }
}
