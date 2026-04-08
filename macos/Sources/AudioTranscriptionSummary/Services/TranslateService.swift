// TranslateService.swift
// Amazon Translate API を使用したリアルタイムテキスト翻訳サービス

import Foundation
import AWSTranslate
import SmithyIdentity

// MARK: - TranslateService

/// Amazon Translate を使用してテキストをリアルタイム翻訳するサービス
/// 指数バックオフによる再試行（最大3回）を実装
final class TranslateService: Sendable {

    private let maxRetries = 3

    /// Amazon Translate の1リクエストあたりの最大バイト数（UTF-8）
    private let maxBytesPerRequest = 9500 // 安全マージンを持たせて9500バイト

    /// テキストを翻訳する（文字数制限を超える場合は文単位で分割翻訳）
    /// - Parameters:
    ///   - text: 翻訳元テキスト
    ///   - sourceLanguage: 翻訳元言語コード（"auto" で自動判別）
    ///   - targetLanguage: 翻訳先言語コード
    ///   - region: AWS リージョン
    /// - Returns: 翻訳されたテキスト
    func translate(
        text: String,
        from sourceLanguage: String = "auto",
        to targetLanguage: String,
        region: String = "ap-northeast-1"
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        // UTF-8バイト数が制限内ならそのまま翻訳
        if text.utf8.count <= maxBytesPerRequest {
            return try await translateChunk(
                text: text, from: sourceLanguage, to: targetLanguage, region: region
            )
        }

        // 文単位で分割して翻訳
        let chunks = splitBySentences(text: text, maxBytes: maxBytesPerRequest)
        var results: [String] = []
        for chunk in chunks {
            let translated = try await translateChunk(
                text: chunk, from: sourceLanguage, to: targetLanguage, region: region
            )
            results.append(translated)
        }
        return results.joined()
    }

    /// テキストを文単位で分割する（前後の文脈を壊さないように句点・改行で区切る）
    private func splitBySentences(text: String, maxBytes: Int) -> [String] {
        // 句点・改行で文を分割
        let delimiters = CharacterSet(charactersIn: "。！？.!?\n")
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if delimiters.contains(char.unicodeScalars.first!) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        // 文をチャンクにまとめる（maxBytes以内）
        var chunks: [String] = []
        var chunk = ""
        for sentence in sentences {
            let combined = chunk + sentence
            if combined.utf8.count > maxBytes && !chunk.isEmpty {
                chunks.append(chunk)
                chunk = sentence
            } else {
                chunk = combined
            }
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    /// 単一チャンクを翻訳する（指数バックオフ再試行付き）
    private func translateChunk(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        region: String
    ) async throws -> String {
        // AWSClientFactory 経由で認証情報を解決
        let resolver = try AWSClientFactory.makeCredentialResolver()

        let config: TranslateClient.TranslateClientConfiguration
        if let resolver = resolver {
            config = try await TranslateClient.TranslateClientConfiguration(
                awsCredentialIdentityResolver: resolver,
                region: region
            )
        } else {
            // SSO プロファイル等: SDK デフォルトの credential resolver を使用
            config = try await TranslateClient.TranslateClientConfiguration(
                region: region
            )
        }
        let client = TranslateClient(config: config)

        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let input = TranslateTextInput(
                    sourceLanguageCode: sourceLanguage,
                    targetLanguageCode: targetLanguage,
                    text: text
                )
                let output = try await client.translateText(input: input)
                return output.translatedText ?? ""
            } catch {
                lastError = error
                let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? NSError(
            domain: "TranslateService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "翻訳に失敗しました"]
        )
    }
}
