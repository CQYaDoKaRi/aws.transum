// ErrorLogger.swift
// エラー発生時に詳細情報をファイルに保存するサービス
// ログは1ファイル（日付時刻.error.log）に集約する

import Foundation

enum ErrorLogger {

    /// 現在のセッション用ログファイル URL（エラー発生時に1回だけ生成）
    private static let logFileURL: URL = {
        let dir = AWSSettingsViewModel.exportDirectory ?? AWSSettingsViewModel.recordingDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let ts = fmt.string(from: Date())
        return dir.appendingPathComponent("\(ts).error.log")
    }()

    /// ログファイルにテキストを追記する共通メソッド
    private static func writeToLog(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }

    /// エラーレポートを追記する
    static func saveErrorLog(error: Error, operation: String, context: [String: String] = [:]) {
        var lines: [String] = []
        lines.append("\n=== エラーレポート ===")
        lines.append("日時: \(Date())")
        lines.append("操作: \(operation)")
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

        writeToLog(lines.joined(separator: "\n") + "\n")
    }
}
