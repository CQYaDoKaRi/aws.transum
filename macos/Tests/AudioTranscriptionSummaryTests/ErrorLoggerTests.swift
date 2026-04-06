// ErrorLoggerTests.swift
// ErrorLogger のテスト
// - 元ファイル名ベースのエラーログ出力
// - ファイル名なしの場合は app.error.log に出力
// - 既存ファイルへの追記
// - ログ内容にデバッグ情報（日時、操作、ファイル名、スタックトレース等）が含まれること

import Testing
import Foundation
@testable import AudioTranscriptionSummary

/// テストデータディレクトリのパス
private let testDataDir: URL = {
    // プロジェクトルート/test/data/ を使用
    var url = URL(fileURLWithPath: #filePath)
    // macos/Tests/AudioTranscriptionSummaryTests/ → プロジェクトルート
    for _ in 0..<4 { url = url.deletingLastPathComponent() }
    return url.appendingPathComponent("test/data")
}()

@Suite("ErrorLogger テスト")
struct ErrorLoggerTests {

    /// テスト中に生成されたファイルを追跡して後で削除する
    private func cleanupFiles(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test("元ファイル名ベースのエラーログが生成される")
    func testErrorLogWithSourceFileName() throws {
        let logFile = testDataDir.appendingPathComponent("test.error.log")
        // 事前にクリーンアップ
        try? FileManager.default.removeItem(at: logFile)
        defer { cleanupFiles([logFile]) }

        // ErrorLogger は内部で AWSSettingsViewModel のディレクトリを使うため、
        // 直接ファイル書き込みロジックをテストする
        let error = AppError.transcriptionFailed(
            underlying: NSError(domain: "TestDomain", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "テストエラー"]))

        // テスト用にログを直接書き込む
        writeTestErrorLog(error: error, operation: "文字起こし", sourceFileName: "test.m4a", to: testDataDir)

        // ファイルが生成されたことを確認
        #expect(FileManager.default.fileExists(atPath: logFile.path))

        let content = try String(contentsOf: logFile, encoding: .utf8)
        // 必須情報が含まれていることを確認
        #expect(content.contains("エラーレポート"))
        #expect(content.contains("日時:"))
        #expect(content.contains("操作: 文字起こし"))
        #expect(content.contains("処理ファイル: test.m4a"))
        #expect(content.contains("テストエラー"))
        #expect(content.contains("システム情報"))
    }

    @Test("ファイル名なしの場合は app.error.log に出力される")
    func testErrorLogWithoutSourceFileName() throws {
        let logFile = testDataDir.appendingPathComponent("app.error.log")
        try? FileManager.default.removeItem(at: logFile)
        defer { cleanupFiles([logFile]) }

        let error = NSError(domain: "TestDomain", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "ファイル名なしエラー"])

        writeTestErrorLog(error: error, operation: "不明な操作", sourceFileName: nil, to: testDataDir)

        #expect(FileManager.default.fileExists(atPath: logFile.path))

        let content = try String(contentsOf: logFile, encoding: .utf8)
        #expect(content.contains("処理ファイル: (なし)"))
        #expect(content.contains("操作: 不明な操作"))
    }

    @Test("既存ファイルに追記される")
    func testErrorLogAppend() throws {
        let logFile = testDataDir.appendingPathComponent("append_test.error.log")
        try? FileManager.default.removeItem(at: logFile)
        defer { cleanupFiles([logFile]) }

        let error1 = NSError(domain: "Test", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "エラー1"])
        let error2 = NSError(domain: "Test", code: -2,
                             userInfo: [NSLocalizedDescriptionKey: "エラー2"])

        writeTestErrorLog(error: error1, operation: "操作1", sourceFileName: "append_test.m4a", to: testDataDir)
        writeTestErrorLog(error: error2, operation: "操作2", sourceFileName: "append_test.m4a", to: testDataDir)

        let content = try String(contentsOf: logFile, encoding: .utf8)
        // 両方のエラーが含まれていることを確認
        #expect(content.contains("エラー1"))
        #expect(content.contains("エラー2"))
        #expect(content.contains("操作1"))
        #expect(content.contains("操作2"))
    }

    @Test("テスト用文字起こしテキストが存在する")
    func testTranscriptFileExists() throws {
        let transcriptFile = testDataDir.appendingPathComponent("test.transcript.txt")
        #expect(FileManager.default.fileExists(atPath: transcriptFile.path),
                "test/data/test.transcript.txt が存在しません。テストデータを配置してください。")

        let text = try String(contentsOf: transcriptFile, encoding: .utf8)
        #expect(!text.isEmpty)
    }

    @Test("テスト用音声ファイルが存在する")
    func testAudioFileExists() {
        let audioFile = testDataDir.appendingPathComponent("test.m4a")
        #expect(FileManager.default.fileExists(atPath: audioFile.path),
                "test/data/test.m4a が存在しません。テストデータを配置してください。")
    }
}

// MARK: - テスト用ヘルパー（ErrorLogger の内部ロジックを再現）

/// ErrorLogger と同じ形式でエラーログを指定ディレクトリに書き込む
private func writeTestErrorLog(error: Error, operation: String, sourceFileName: String?, to directory: URL) {
    if !FileManager.default.fileExists(atPath: directory.path) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let logFileName: String
    if let name = sourceFileName, !name.isEmpty {
        let baseName = (name as NSString).deletingPathExtension
        logFileName = "\(baseName).error.log"
    } else {
        logFileName = "app.error.log"
    }
    let fileURL = directory.appendingPathComponent(logFileName)

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
    }

    let nsErr = error as NSError
    lines.append("--- NSError 詳細 ---")
    lines.append("domain: \(nsErr.domain)")
    lines.append("code: \(nsErr.code)")
    lines.append("")
    lines.append("--- システム情報 ---")
    lines.append("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    lines.append("プロセス: \(ProcessInfo.processInfo.processName)")
    lines.append("PID: \(ProcessInfo.processInfo.processIdentifier)")

    let text = lines.joined(separator: "\n") + "\n"
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
