// BedrockModel.swift
// Bedrock 基盤モデルの選択肢（Cross-Region inference 対応）
// モデル ID は AWS ドキュメントの公式 ID を使用

import Foundation

struct BedrockModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let usInferenceId: String?
    let euInferenceId: String?
    let globalInferenceId: String?

    func isAvailable(in region: String) -> Bool {
        if region.hasPrefix("us-") { return true }
        if region.hasPrefix("eu-") || region.hasPrefix("il-") { return euInferenceId != nil }
        return globalInferenceId != nil
    }

    func inferenceId(for region: String) -> String {
        if region.hasPrefix("us-") { return usInferenceId ?? id }
        if region.hasPrefix("eu-") || region.hasPrefix("il-") { return euInferenceId ?? globalInferenceId ?? id }
        if let global = globalInferenceId { return global }
        return usInferenceId ?? id
    }

    static let available: [BedrockModel] = [
        .init(id: "anthropic.claude-sonnet-4-6", name: "Claude Sonnet 4.6", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-sonnet-4-6",
              euInferenceId: "eu.anthropic.claude-sonnet-4-6",
              globalInferenceId: "global.anthropic.claude-sonnet-4-6"),
        .init(id: "anthropic.claude-opus-4-6-v1", name: "Claude Opus 4.6", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-opus-4-6-v1",
              euInferenceId: "eu.anthropic.claude-opus-4-6-v1",
              globalInferenceId: "global.anthropic.claude-opus-4-6-v1"),
        .init(id: "anthropic.claude-sonnet-4-5-20250929-v1:0", name: "Claude Sonnet 4.5", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
              euInferenceId: "eu.anthropic.claude-sonnet-4-5-20250929-v1:0",
              globalInferenceId: "global.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        .init(id: "anthropic.claude-sonnet-4-20250514-v1:0", name: "Claude Sonnet 4", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-sonnet-4-20250514-v1:0",
              euInferenceId: "eu.anthropic.claude-sonnet-4-20250514-v1:0",
              globalInferenceId: "global.anthropic.claude-sonnet-4-20250514-v1:0"),
        .init(id: "anthropic.claude-3-5-sonnet-20241022-v2:0", name: "Claude 3.5 Sonnet v2", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
              euInferenceId: "eu.anthropic.claude-3-5-sonnet-20241022-v2:0",
              globalInferenceId: nil),
        .init(id: "anthropic.claude-3-5-haiku-20241022-v1:0", name: "Claude 3.5 Haiku", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-3-5-haiku-20241022-v1:0",
              euInferenceId: "eu.anthropic.claude-3-5-haiku-20241022-v1:0",
              globalInferenceId: nil),
        .init(id: "anthropic.claude-3-haiku-20240307-v1:0", name: "Claude 3 Haiku", provider: "Anthropic",
              usInferenceId: "us.anthropic.claude-3-haiku-20240307-v1:0",
              euInferenceId: "eu.anthropic.claude-3-haiku-20240307-v1:0",
              globalInferenceId: nil),
        .init(id: "amazon.titan-text-express-v1", name: "Titan Text Express", provider: "Amazon",
              usInferenceId: nil, euInferenceId: nil, globalInferenceId: "amazon.titan-text-express-v1"),
        .init(id: "amazon.titan-text-lite-v1", name: "Titan Text Lite", provider: "Amazon",
              usInferenceId: nil, euInferenceId: nil, globalInferenceId: "amazon.titan-text-lite-v1"),
    ]

    static func find(by id: String) -> BedrockModel? {
        available.first { $0.id == id }
    }

    static func availableModels(for region: String) -> [BedrockModel] {
        available.filter { $0.isAvailable(in: region) }
    }
}
