// AppError.swift
// アプリケーション全体で使用するエラー型の定義

import Foundation

// MARK: - AppError（アプリケーションエラー）

/// アプリケーション全体で発生しうるエラーを統一的に管理する列挙型
enum AppError: LocalizedError, Sendable {
    /// サポート対象外のファイル形式
    case unsupportedFormat(String, supportedFormats: [String])
    /// ファイルが破損している
    case corruptedFile
    /// 文字起こし処理の失敗
    case transcriptionFailed(underlying: any Error)
    /// 音声が検出されなかった（無音）
    case silentAudio
    /// 要約処理の失敗
    case summarizationFailed(underlying: any Error)
    /// 要約するには内容が不十分
    case insufficientContent(minimumCharacters: Int)
    /// エクスポート処理の失敗
    case exportFailed(underlying: any Error)
    /// 保存先への書き込み権限がない
    case writePermissionDenied(path: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext, let supported):
            return "「.\(ext)」形式はサポートされていません。対応形式: \(supported.joined(separator: ", "))"
        case .corruptedFile:
            return "ファイルが読み込めません"
        case .transcriptionFailed(let error):
            return "文字起こしに失敗しました: \(error.localizedDescription)"
        case .silentAudio:
            return "音声が検出されませんでした"
        case .summarizationFailed(let error):
            return "要約に失敗しました: \(error.localizedDescription)"
        case .insufficientContent(let min):
            return "要約するには内容が不十分です（最低\(min)文字必要）"
        case .exportFailed(let error):
            return "エクスポートに失敗しました: \(error.localizedDescription)"
        case .writePermissionDenied:
            return "保存先に書き込みできません。別のフォルダを選択してください"
        }
    }
}
