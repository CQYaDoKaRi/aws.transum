// BedrockModel.swift
// Bedrock 基盤モデルの選択肢

import Foundation

struct BedrockModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String

    static let available: [BedrockModel] = [
        // Claude 4.x 系（最新）
        .init(id: "anthropic.claude-sonnet-4-6-20260617-v1:0", name: "Claude Sonnet 4.6", provider: "Anthropic"),
        .init(id: "anthropic.claude-opus-4-6-20260514-v1:0", name: "Claude Opus 4.6", provider: "Anthropic"),
        .init(id: "anthropic.claude-sonnet-4-5-20250929-v1:0", name: "Claude Sonnet 4.5", provider: "Anthropic"),
        .init(id: "anthropic.claude-opus-4-5-20251101-v1:0", name: "Claude Opus 4.5", provider: "Anthropic"),
        .init(id: "anthropic.claude-sonnet-4-20250514-v1:0", name: "Claude Sonnet 4", provider: "Anthropic"),
        // Claude 3.x 系
        .init(id: "anthropic.claude-3-5-sonnet-20241022-v2:0", name: "Claude 3.5 Sonnet v2", provider: "Anthropic"),
        .init(id: "anthropic.claude-3-5-haiku-20241022-v1:0", name: "Claude 3.5 Haiku", provider: "Anthropic"),
        .init(id: "anthropic.claude-3-haiku-20240307-v1:0", name: "Claude 3 Haiku", provider: "Anthropic"),
        .init(id: "anthropic.claude-3-sonnet-20240229-v1:0", name: "Claude 3 Sonnet", provider: "Anthropic"),
        // Amazon Titan
        .init(id: "amazon.titan-text-express-v1", name: "Titan Text Express", provider: "Amazon"),
        .init(id: "amazon.titan-text-lite-v1", name: "Titan Text Lite", provider: "Amazon"),
    ]

    static func find(by id: String) -> BedrockModel? {
        available.first { $0.id == id }
    }
}
