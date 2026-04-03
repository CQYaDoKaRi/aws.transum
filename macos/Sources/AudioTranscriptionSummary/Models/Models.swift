// Models.swift
// データモデル定義
// AudioFile, Transcript, Summary, TranscriptionLanguage のモデルをここに定義する

import Foundation

// MARK: - TranscriptionLanguage（文字起こし言語）

/// 文字起こしに使用する言語を表す列挙型
enum TranscriptionLanguage: String {
    /// 自動判定
    case auto = "auto"
    /// 日本語
    case japanese = "ja-JP"
    /// 英語
    case english = "en-US"
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
