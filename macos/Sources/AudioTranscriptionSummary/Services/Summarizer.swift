// Summarizer.swift
// 文字起こしテキストの要約を担当するサービス
// NaturalLanguage フレームワークを用いた抽出型要約（extractive summarization）を実装する

import Foundation
import NaturalLanguage

// MARK: - Summarizer（要約サービス）

/// Summarizing プロトコルに準拠した要約サービス
/// NLTokenizer を用いて文分割を行い、スコアリングに基づく抽出型要約を生成する
final class Summarizer: Summarizing {

    /// 要約可能な最小文字数
    static let minimumCharacterCount: Int = 50

    /// Transcript の要約を生成する
    /// - Parameter transcript: 要約対象の Transcript
    /// - Returns: 生成された Summary
    /// - Throws: `AppError.insufficientContent` または `AppError.summarizationFailed`
    func summarize(transcript: Transcript) async throws -> Summary {
        // 文字数チェック（50文字未満は拒否）
        guard transcript.characterCount >= Summarizer.minimumCharacterCount else {
            throw AppError.insufficientContent(minimumCharacters: Summarizer.minimumCharacterCount)
        }

        let text = transcript.text

        // テキストの前処理：文分割
        let sentences = splitIntoSentences(text: text)

        // 文が1つ以下の場合はそのまま返す
        guard sentences.count > 1 else {
            return Summary(
                id: UUID(),
                transcriptId: transcript.id,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: Date()
            )
        }

        // 要約処理の実行
        let summaryText = extractSummary(sentences: sentences, originalText: text)

        return Summary(
            id: UUID(),
            transcriptId: transcript.id,
            text: summaryText,
            createdAt: Date()
        )
    }

    // MARK: - Private Methods

    /// NLTokenizer を用いてテキストを文に分割する
    /// - Parameter text: 分割対象のテキスト
    /// - Returns: 文の配列
    private func splitIntoSentences(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }

    /// 抽出型要約を実行する
    /// スコアの高い文を選択して要約を構成する
    /// - Parameters:
    ///   - sentences: 文の配列
    ///   - originalText: 元のテキスト
    /// - Returns: 要約テキスト
    private func extractSummary(sentences: [String], originalText: String) -> String {
        // 単語の出現頻度を計算
        let wordFrequencies = calculateWordFrequencies(text: originalText)

        // 各文のスコアを計算
        let scoredSentences = sentences.enumerated().map { index, sentence in
            let score = calculateSentenceScore(
                sentence: sentence,
                index: index,
                totalSentences: sentences.count,
                wordFrequencies: wordFrequencies
            )
            return (index: index, sentence: sentence, score: score)
        }

        // 選択する文の数を決定（全体の約30%、最低1文）
        let selectionCount = max(1, Int(ceil(Double(sentences.count) * 0.3)))

        // スコア順にソートし、上位の文を選択
        let topSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(selectionCount)

        // 元の文順序を維持して結合
        let orderedSentences = topSentences
            .sorted { $0.index < $1.index }
            .map { $0.sentence }

        return orderedSentences.joined(separator: " ")
    }

    /// テキスト内の単語出現頻度を計算する
    /// NLTokenizer を用いて単語に分割し、頻度をカウントする
    /// - Parameter text: 対象テキスト
    /// - Returns: 単語と出現頻度の辞書
    private func calculateWordFrequencies(text: String) -> [String: Int] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var frequencies: [String: Int] = [:]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            // 1文字以下の単語は無視（助詞・記号など）
            if word.count > 1 {
                frequencies[word, default: 0] += 1
            }
            return true
        }

        return frequencies
    }

    /// 文のスコアを計算する
    /// 文の長さ、位置、キーワード出現頻度を考慮してスコアリングする
    /// - Parameters:
    ///   - sentence: スコア計算対象の文
    ///   - index: 文の位置（0始まり）
    ///   - totalSentences: 全文数
    ///   - wordFrequencies: 単語出現頻度の辞書
    /// - Returns: 文のスコア（高いほど重要）
    private func calculateSentenceScore(
        sentence: String,
        index: Int,
        totalSentences: Int,
        wordFrequencies: [String: Int]
    ) -> Double {
        var score: Double = 0.0

        // 1. 位置スコア：最初と最後の文を重視
        let positionScore = calculatePositionScore(index: index, totalSentences: totalSentences)
        score += positionScore

        // 2. キーワード頻度スコア：高頻度の単語を含む文を重視
        let frequencyScore = calculateFrequencyScore(
            sentence: sentence,
            wordFrequencies: wordFrequencies
        )
        score += frequencyScore

        // 3. 文の長さスコア：極端に短い・長い文にペナルティ
        let lengthScore = calculateLengthScore(sentence: sentence)
        score += lengthScore

        return score
    }

    /// 位置スコアを計算する
    /// 最初の文と最後の文に高いスコアを付与する
    private func calculatePositionScore(index: Int, totalSentences: Int) -> Double {
        if index == 0 {
            // 最初の文は最も重要
            return 1.0
        } else if index == totalSentences - 1 {
            // 最後の文も重要
            return 0.5
        } else {
            // 前半の文をやや重視
            let normalizedPosition = 1.0 - (Double(index) / Double(totalSentences))
            return normalizedPosition * 0.3
        }
    }

    /// キーワード頻度スコアを計算する
    /// 文中の単語の出現頻度の平均値を正規化して返す
    private func calculateFrequencyScore(
        sentence: String,
        wordFrequencies: [String: Int]
    ) -> Double {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = sentence

        var totalFrequency: Double = 0.0
        var wordCount: Double = 0.0

        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
            let word = String(sentence[range]).lowercased()
            if word.count > 1, let frequency = wordFrequencies[word] {
                totalFrequency += Double(frequency)
                wordCount += 1.0
            }
            return true
        }

        guard wordCount > 0 else { return 0.0 }

        // 最大頻度で正規化
        let maxFrequency = Double(wordFrequencies.values.max() ?? 1)
        return (totalFrequency / wordCount) / maxFrequency
    }

    /// 文の長さスコアを計算する
    /// 適度な長さの文に高いスコアを付与する
    private func calculateLengthScore(sentence: String) -> Double {
        let length = sentence.count
        // 10〜100文字の範囲を理想的な長さとする
        if length < 5 {
            return 0.0
        } else if length < 10 {
            return 0.2
        } else if length <= 100 {
            return 0.5
        } else {
            // 長すぎる文にはやや低いスコア
            return 0.3
        }
    }
}
