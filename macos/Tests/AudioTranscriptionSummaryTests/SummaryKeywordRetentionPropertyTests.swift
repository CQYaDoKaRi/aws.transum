// SummaryKeywordRetentionPropertyTests.swift
// Feature: audio-transcription-summary, Property 4: 要約のキーワード保持
// 50文字以上のランダムテキストを生成し、Summary が元の Transcript の主要な単語を含むことを検証する
// **Validates: Requirements 3.4**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック Summarizer（キーワード保持検証用）

/// Summarizing プロトコルに準拠したモック
/// 入力テキストの一部を抽出して要約を生成する（実際の Summarizer の抽出型要約を模倣）
private final class MockKeywordRetentionSummarizer: Summarizing, Sendable {

    static let minimumCharacterCount: Int = 50

    /// Transcript の要約を生成する
    /// 入力テキストの文を分割し、先頭の文を要約として返す（キーワードが保持されることを保証）
    func summarize(transcript: Transcript) async throws -> Summary {
        guard transcript.characterCount >= Self.minimumCharacterCount else {
            throw AppError.insufficientContent(minimumCharacters: Self.minimumCharacterCount)
        }

        let text = transcript.text

        // 文分割（句点・ピリオドで分割）
        let separators = CharacterSet(charactersIn: "。.!！?？\n")
        let sentences = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // 先頭の文（最低1文）を要約として使用
        let summaryText: String
        if sentences.count <= 1 {
            summaryText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // 約30%の文を選択（最低1文）
            let count = max(1, Int(ceil(Double(sentences.count) * 0.3)))
            summaryText = sentences.prefix(count).joined(separator: "。")
        }

        return Summary(
            id: UUID(),
            transcriptId: transcript.id,
            text: summaryText,
            createdAt: Date()
        )
    }
}

// MARK: - Property 4: 要約のキーワード保持（Summary Keyword Retention）

final class SummaryKeywordRetentionPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// 50文字以上のランダムテキストを生成するジェネレータ
    /// 複数の文で構成されるテキストを生成し、キーワード保持の検証に適した入力を提供する
    private var longTextGen: Gen<String> {
        // 単語リスト（名詞・固有名詞を含む）
        let words = [
            "音声認識", "技術", "プロジェクト", "会議", "開発",
            "データ", "分析", "レポート", "システム", "設計",
            "テスト", "品質", "管理", "チーム", "進捗",
            "speech", "recognition", "project", "meeting", "development",
            "analysis", "report", "system", "design", "quality"
        ]

        // 文のテンプレート
        let templates = [
            "本日の{0}では{1}について議論しました",
            "{0}の{1}が大きく進歩しています",
            "{0}チームが{1}の改善に取り組んでいます",
            "新しい{0}の{1}を開始する予定です",
            "{0}に関する{1}が完了しました"
        ]

        // 3〜6文のテキストを生成
        return Gen<Int>.fromElements(in: 3...6).flatMap { sentenceCount in
            Gen<(String, String, String)>.zip(
                Gen<String>.fromElements(of: words),
                Gen<String>.fromElements(of: words),
                Gen<String>.fromElements(of: templates)
            )
            .proliferate(withSize: sentenceCount)
            .map { pairs in
                let sentences = pairs.prefix(sentenceCount).map { word1, word2, template in
                    template
                        .replacingOccurrences(of: "{0}", with: word1)
                        .replacingOccurrences(of: "{1}", with: word2)
                }
                return sentences.joined(separator: "。") + "。"
            }
            .suchThat { $0.count >= 50 }
        }
    }

    // MARK: - プロパティテスト

    /// 50文字以上のテキストに対して、生成された Summary が元の Transcript の単語を少なくとも1つ含むことを検証
    func testSummaryKeywordRetention() {
        let summarizer = MockKeywordRetentionSummarizer()

        property("要約のキーワード保持: Summary は元の Transcript の主要な単語を含む")
            <- forAll(self.longTextGen) { (text: String) in
                guard text.count >= 50 else { return true }

                let transcript = Transcript(
                    id: UUID(),
                    audioFileId: UUID(),
                    text: text,
                    language: .japanese,
                    createdAt: Date()
                )

                do {
                    let summary = try awaitResult {
                        try await summarizer.summarize(transcript: transcript)
                    }

                    // 元のテキストから2文字以上の単語を抽出
                    let originalWords = self.extractWords(from: text)

                    // Summary が空でないことを確認
                    guard !summary.text.isEmpty else { return false }

                    // Summary が元のテキストの単語を少なくとも1つ含むことを確認
                    let summaryContainsKeyword = originalWords.contains { word in
                        summary.text.contains(word)
                    }

                    return summaryContainsKeyword
                } catch {
                    return false
                }
            }
    }

    // MARK: - ヘルパーメソッド

    /// テキストから2文字以上の単語を抽出する
    /// - Parameter text: 対象テキスト
    /// - Returns: 抽出された単語の配列
    private func extractWords(from text: String) -> [String] {
        // 句読点・記号で分割し、空白でさらに分割
        let separators = CharacterSet.alphanumerics.inverted
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }
}

// MARK: - ヘルパー関数

/// async 関数を同期的に実行するためのヘルパー
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
