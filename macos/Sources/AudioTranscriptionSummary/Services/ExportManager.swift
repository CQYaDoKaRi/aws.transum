// ExportManager.swift
// 文字起こし結果と要約のエクスポートを担当するサービス
// UTF-8 エンコーディングの .txt ファイルとして出力する

import Foundation

// MARK: - ExportManager（エクスポートサービス）

/// Exporting プロトコルに準拠したエクスポートサービス
/// Transcript と Summary を単一の UTF-8 テキストファイルとして保存する
final class ExportManager: Exporting, Sendable {

    // MARK: - 日付フォーマッター

    /// ファイル名に使用する日付フォーマッター（transcript_YYYYMMDD_HHmmss.txt）
    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    // MARK: - 書き込み権限の確認

    /// 指定ディレクトリへの書き込み権限を確認する
    /// - Parameter directory: 確認するディレクトリの URL
    /// - Returns: 書き込み可能であれば true
    func canWrite(to directory: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: directory.path)
    }

    // MARK: - エクスポート

    /// Transcript と Summary をテキストファイルとして保存する
    ///
    /// 処理フロー:
    /// 1. 書き込み権限の確認
    /// 2. エクスポート内容の組み立て
    /// 3. ファイル名の生成（transcript_YYYYMMDD_HHmmss.txt）
    /// 4. UTF-8 エンコーディングでファイルに書き出し
    ///
    /// - Parameters:
    ///   - transcript: エクスポートする Transcript
    ///   - summary: エクスポートする Summary（省略可）
    ///   - directory: 保存先ディレクトリの URL
    /// - Returns: 保存されたファイルの URL
    /// - Throws: `AppError.writePermissionDenied` または `AppError.exportFailed`
    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL {
        // 1. 書き込み権限の確認
        guard canWrite(to: directory) else {
            throw AppError.writePermissionDenied(path: directory.path)
        }

        // 2. エクスポート内容の組み立て
        let content = buildExportContent(transcript: transcript, summary: summary)

        // 3. ファイル名の生成
        let fileName = generateFileName(date: transcript.createdAt)
        let fileURL = directory.appendingPathComponent(fileName)

        // 4. UTF-8 エンコーディングでファイルに書き出し
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.exportFailed(underlying: error)
        }

        return fileURL
    }

    // MARK: - Private Methods

    /// エクスポートするテキスト内容を組み立てる
    /// - Parameters:
    ///   - transcript: Transcript データ
    ///   - summary: Summary データ（省略可）
    /// - Returns: エクスポート用のテキスト文字列
    private func buildExportContent(transcript: Transcript, summary: Summary?) -> String {
        var lines: [String] = []

        // Transcript セクション
        lines.append("=== Transcript ===")
        lines.append(transcript.text)

        // Summary セクション（存在する場合のみ）
        if let summary = summary {
            lines.append("")
            lines.append("=== Summary ===")
            lines.append(summary.text)
        }

        return lines.joined(separator: "\n")
    }

    /// ファイル名を生成する（transcript_YYYYMMDD_HHmmss.txt）
    /// - Parameter date: ファイル名に使用する日付
    /// - Returns: 生成されたファイル名
    private func generateFileName(date: Date) -> String {
        let dateString = Self.fileNameFormatter.string(from: date)
        return "transcript_\(dateString).txt"
    }
}
