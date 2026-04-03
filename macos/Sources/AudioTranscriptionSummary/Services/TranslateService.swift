// TranslateService.swift
// Amazon Translate API を使用したリアルタイムテキスト翻訳サービス

import Foundation
import AWSTranslate

// MARK: - TranslateService

/// Amazon Translate を使用してテキストをリアルタイム翻訳するサービス
/// 指数バックオフによる再試行（最大3回）を実装
final class TranslateService: Sendable {

    private let maxRetries = 3

    /// テキストを翻訳する
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

        let config = try await TranslateClient.TranslateClientConfiguration(
            region: region
        )
        let client = TranslateClient(config: config)

        var lastError: Error?

        // 指数バックオフによる再試行
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
                // 指数バックオフ: 1秒, 2秒, 4秒
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
