// TranslationLanguage.swift
// リアルタイム翻訳の対象言語を定義する列挙型

import Foundation

/// Amazon Translate でサポートする翻訳先言語
enum TranslationLanguage: String, CaseIterable, Identifiable, Codable {
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    /// UI 表示用の言語名
    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .chinese: return "中文"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }
}
