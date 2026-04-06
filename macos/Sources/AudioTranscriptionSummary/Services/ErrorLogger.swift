// ErrorLogger.swift
// エラー発生時に詳細情報をファイルに保存するサービス
// 元ファイル名.error.log に追記、ファイル名がない場合は app.error.log に追記

import Foundation

enum ErrorLogger {

    /// ログ出力先ディレクトリを返す
    private static var logDirectory: URL {
        AWSSettingsViewModel.exportDirectory ?? AWSSettingsViewModel.recordingDirectory
    }

    /// 元ファイル名からログファイル URL を決定する
    /// - Parameter sourceFileName: 処理中のファイル名（nil の場合は app.error.log）
    private static func logFileURL(sourceFileName: String?) -> URL {
        let dir = logDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let name = sourceFileName, !name.isEmpty {
            // 拡張子を除いたベース名.error.log
            let baseName = (name as NSString).deletingPathExtension
            return dir.appendingPathComponent("\(baseName).error.log")
        }
        return dir.appendingPathComponent("app.error.log")
    }

    /// ログファイルにテキストを追記する共通メソッド
    private static func writeToLog(_ text: String, fileURL: URL) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// エラーレポートを追記する
    /// - Parameters:
    ///   - error: 発生したエラー
    ///   - operation: 実行中の操作名
    ///   - sourceFileName: 処理中の元ファイル名（nil の場合は app.error.log に出力）
    ///   - context: 追加のコンテキスト情報
    static func saveErrorLog(error: Error, operation: String, sourceFileName: String? = nil, context: [String: String] = [:]) {
        let fileURL = logFileURL(sourceFileName: sourceFileName)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var lines: [String] = []
        lines.append("\n=== エラーレポート ===")
        lines.append("日時: \(fmt.string(from: Date()))")
        lines.append("操作: \(operation)")
        lines.append("処理ファイル: \(sourceFileName ?? "(なし)")")
        lines.append("")
        lines.append("--- エラー概要 ---")
        lines.append("説明: \(error.localizedDescription)")
        lines.append("型: \(type(of: error))")
        lines.append("")

        if let appErr = error as? AppError {
            lines.append("--- AppError 詳細 ---")
            lines.append("errorDescription: \(appErr.errorDescription ?? "nil")")
            if case .transcriptionFailed(let underlying) = appErr {
                lines.append("underlying: \(underlying)")
                lines.append("underlying.localizedDescription: \(underlying.localizedDescription)")
                let ns = underlying as NSError
                lines.append("domain: \(ns.domain)")
                lines.append("code: \(ns.code)")
                lines.append("userInfo: \(ns.userInfo)")
            }
        }

        let nsErr = error as NSError
        lines.append("")
        lines.append("--- NSError 詳細 ---")
        lines.append("domain: \(nsErr.domain)")
        lines.append("code: \(nsErr.code)")
        lines.append("userInfo: \(nsErr.userInfo)")
        if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] {
            lines.append("underlyingError: \(underlying)")
        }

        let code = nsErr.code
        if code > 0 {
            let chars = [
                Character(UnicodeScalar((code >> 24) & 0xFF)!),
                Character(UnicodeScalar((code >> 16) & 0xFF)!),
                Character(UnicodeScalar((code >> 8) & 0xFF)!),
                Character(UnicodeScalar(code & 0xFF)!)
            ]
            lines.append("OSStatus FourCC: '\(String(chars))'")
        }

        lines.append("")
        lines.append("--- スタックトレース ---")
        for symbol in Thread.callStackSymbols.prefix(20) {
            lines.append(symbol)
        }

        lines.append("")
        lines.append("--- 追加情報 ---")
        lines.append("rawFileURL: \(context["rawFileURL"] ?? "nil")")
        lines.append("finalFileURL: \(context["finalFileURL"] ?? "nil")")
        if let rawFileURL = context["rawFileURL"] {
            let exists = FileManager.default.fileExists(atPath: rawFileURL)
            lines.append("rawFile exists: \(exists)")
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: rawFileURL) {
                lines.append("rawFile size: \(attrs[.size] ?? 0)")
            }
        }
        if let finalFileURL = context["finalFileURL"] {
            let exists = FileManager.default.fileExists(atPath: finalFileURL)
            lines.append("finalFile exists: \(exists)")
        }

        lines.append("")
        lines.append("--- コンテキスト ---")
        for (key, value) in context.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key): \(value)")
        }

        lines.append("")
        lines.append("--- システム情報 ---")
        lines.append("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("プロセス: \(ProcessInfo.processInfo.processName)")
        lines.append("PID: \(ProcessInfo.processInfo.processIdentifier)")
        lines.append("メモリ: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
        lines.append("CPU数: \(ProcessInfo.processInfo.processorCount)")

        writeToLog(lines.joined(separator: "\n") + "\n", fileURL: fileURL)
    }
}
