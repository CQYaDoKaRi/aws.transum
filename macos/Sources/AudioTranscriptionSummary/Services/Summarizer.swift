// Summarizer.swift
// Amazon Bedrock（Claude）を使用した生成型要約サービス
// AWS 認証情報が未設定の場合は NaturalLanguage フレームワークによるローカル抽出型要約にフォールバック

import Foundation
import NaturalLanguage
import AWSBedrockRuntime

final class Summarizer: Summarizing, @unchecked Sendable {

    static let minimumCharacterCount: Int = 50

    func summarize(transcript: Transcript) async throws -> Summary {
        try await summarize(transcript: transcript, additionalPrompt: "")
    }

    func summarize(transcript: Transcript, additionalPrompt: String) async throws -> Summary {
        guard transcript.characterCount >= Summarizer.minimumCharacterCount else {
            throw AppError.insufficientContent(minimumCharacters: Summarizer.minimumCharacterCount)
        }

        if AWSSettingsViewModel.hasValidCredentials {
            do {
                let summaryText = try await summarizeWithBedrock(text: transcript.text, additionalPrompt: additionalPrompt)
                return Summary(id: UUID(), transcriptId: transcript.id, text: summaryText, createdAt: Date())
            } catch {
                ErrorLogger.saveErrorLog(error: error, operation: "Bedrock要約失敗_フォールバック", context: [:])
            }
        }

        let summaryText = localExtractSummary(text: transcript.text)
        return Summary(id: UUID(), transcriptId: transcript.id, text: summaryText, createdAt: Date())
    }

    // MARK: - Bedrock（Claude）要約

    private func summarizeWithBedrock(text: String, additionalPrompt: String = "") async throws -> String {
        let region = AWSSettingsViewModel.currentRegion
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfiguration(region: region)
        let client = BedrockRuntimeClient(config: config)

        let modelId = AWSSettingsViewModel.currentBedrockModelId

        // プロンプト
        var prompt = """
        以下のテキストを簡潔に要約してください。要約は元のテキストの言語で出力してください。箇条書きではなく、自然な文章で要約してください。
        """
        if !additionalPrompt.isEmpty {
            prompt += "\n\n追加の指示:\n\(additionalPrompt)"
        }
        prompt += "\n\nテキスト:\n\(text)"

        // Converse API を使用
        let message = BedrockRuntimeClientTypes.Message(
            content: [.text(prompt)],
            role: .user
        )

        let input = ConverseInput(
            inferenceConfig: .init(maxTokens: 1024, temperature: 0.3),
            messages: [message],
            modelId: modelId
        )

        let output = try await client.converse(input: input)

        // レスポンスからテキストを抽出
        guard let responseMessage = output.output,
              case .message(let msg) = responseMessage,
              let firstContent = msg.content?.first,
              case .text(let summaryText) = firstContent else {
            throw AppError.summarizationFailed(
                underlying: NSError(domain: "Summarizer", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Bedrock からの応答を解析できませんでした"]))
        }

        return summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - ローカル抽出型要約（フォールバック）

    private func localExtractSummary(text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }

        guard sentences.count > 1 else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 単語頻度計算
        let wordTokenizer = NLTokenizer(unit: .word)
        wordTokenizer.string = text
        var freq: [String: Int] = [:]
        wordTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let w = String(text[range]).lowercased()
            if w.count > 1 { freq[w, default: 0] += 1 }
            return true
        }

        // スコアリング
        let maxFreq = Double(freq.values.max() ?? 1)
        let scored = sentences.enumerated().map { i, s -> (Int, String, Double) in
            var score = i == 0 ? 1.0 : (i == sentences.count - 1 ? 0.5 : (1.0 - Double(i) / Double(sentences.count)) * 0.3)
            let wt = NLTokenizer(unit: .word); wt.string = s
            var wSum = 0.0, wCnt = 0.0
            wt.enumerateTokens(in: s.startIndex..<s.endIndex) { r, _ in
                let w = String(s[r]).lowercased()
                if w.count > 1, let f = freq[w] { wSum += Double(f); wCnt += 1 }
                return true
            }
            if wCnt > 0 { score += (wSum / wCnt) / maxFreq }
            return (i, s, score)
        }

        let count = max(1, Int(ceil(Double(sentences.count) * 0.3)))
        return scored.sorted { $0.2 > $1.2 }.prefix(count).sorted { $0.0 < $1.0 }.map { $0.1 }.joined(separator: " ")
    }
}
