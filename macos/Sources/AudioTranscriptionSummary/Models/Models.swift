// Models.swift
// データモデル定義
// AudioFile, Transcript, Summary, TranscriptionLanguage のモデルをここに定義する

import Foundation

// MARK: - TranscriptionLanguage（文字起こし言語）

/// 文字起こしに使用する言語を表す列挙型（Amazon Transcribe 対応言語）
enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case auto = "auto"
    case japanese = "ja-JP"
    case english = "en-US"
    case chinese = "zh-CN"
    case korean = "ko-KR"
    case french = "fr-FR"
    case german = "de-DE"
    case spanish = "es-ES"
    case portuguese = "pt-BR"
    case italian = "it-IT"
    case hindi = "hi-IN"
    case arabic = "ar-SA"
    case russian = "ru-RU"
    case turkish = "tr-TR"
    case dutch = "nl-NL"
    case swedish = "sv-SE"
    case polish = "pl-PL"
    case thai = "th-TH"
    case indonesian = "id-ID"
    case vietnamese = "vi-VN"
    case malay = "ms-MY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "言語自動判定"
        case .japanese: return "日本語"
        case .english: return "英語"
        case .chinese: return "中国語"
        case .korean: return "韓国語"
        case .french: return "フランス語"
        case .german: return "ドイツ語"
        case .spanish: return "スペイン語"
        case .portuguese: return "ポルトガル語"
        case .italian: return "イタリア語"
        case .hindi: return "ヒンディー語"
        case .arabic: return "アラビア語"
        case .russian: return "ロシア語"
        case .turkish: return "トルコ語"
        case .dutch: return "オランダ語"
        case .swedish: return "スウェーデン語"
        case .polish: return "ポーランド語"
        case .thai: return "タイ語"
        case .indonesian: return "インドネシア語"
        case .vietnamese: return "ベトナム語"
        case .malay: return "マレー語"
        }
    }
}

// MARK: - AudioFile（音声ファイル）

/// 読み込まれた音声ファイルの情報を保持する構造体
struct AudioFile: Equatable {
    /// 一意な識別子
    let id: UUID
    /// 音声ファイルの URL
    let url: URL
    /// ファイル名（拡張子なし）
    let fileName: String
    /// ファイルの拡張子（例: "m4a", "wav"）
    let fileExtension: String
    /// 再生時間（秒）
    let duration: TimeInterval
    /// ファイルサイズ（バイト）
    let fileSize: Int64
    /// 作成日時
    let createdAt: Date
}

// MARK: - Transcript（文字起こし結果）

/// 音声ファイルから生成された文字起こしテキストを保持する構造体
struct Transcript: Equatable {
    /// 一意な識別子
    let id: UUID
    /// 関連する音声ファイルの ID
    let audioFileId: UUID
    /// 文字起こしテキスト
    let text: String
    /// 文字起こしに使用した言語
    let language: TranscriptionLanguage
    /// 作成日時
    let createdAt: Date

    /// テキストが空かどうか（空白・改行のみの場合も空とみなす）
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 文字数
    var characterCount: Int { text.count }
}

// MARK: - Summary（要約）

/// 文字起こしテキストから生成された要約を保持する構造体
struct Summary: Equatable {
    /// 一意な識別子
    let id: UUID
    /// 関連する Transcript の ID
    let transcriptId: UUID
    /// 要約テキスト
    let text: String
    /// 作成日時
    let createdAt: Date
}
