#!/usr/bin/env swift
// run_tests.swift
// XCTest/Testing 不要の独立テストランナー
// 使い方: swift test/macos/run_tests.swift

import Foundation

// MARK: - テストフレームワーク

var totalTests = 0
var passedTests = 0
var failedTests: [(String, String)] = []

func test(_ name: String, _ body: () throws -> Void) {
    totalTests += 1
    do {
        try body()
        passedTests += 1
        print("  ✅ \(name)")
    } catch {
        failedTests.append((name, "\(error)"))
        print("  ❌ \(name): \(error)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #file, line: Int = #line) throws {
    guard a == b else { throw TestError.assertionFailed("期待値: \(b), 実際: \(a) (\(file):\(line))") }
}

func assertTrue(_ v: Bool, _ msg: String = "", file: String = #file, line: Int = #line) throws {
    guard v else { throw TestError.assertionFailed(msg.isEmpty ? "false (\(file):\(line))" : msg) }
}

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)
    var description: String { if case .assertionFailed(let m) = self { return m }; return "" }
}

// MARK: - テストデータディレクトリ

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let testDataDir = scriptURL
    .deletingLastPathComponent()  // macos/
    .deletingLastPathComponent()  // test/
    .appendingPathComponent("data")

func cleanup(_ names: [String]) {
    for name in names {
        try? FileManager.default.removeItem(at: testDataDir.appendingPathComponent(name))
    }
}

// MARK: - ErrorLogger ロジック

func writeErrorLog(error: Error, operation: String, sourceFileName: String?, to directory: URL) {
    if !FileManager.default.fileExists(atPath: directory.path) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let logFileName: String
    if let name = sourceFileName, !name.isEmpty {
        logFileName = "\((name as NSString).deletingPathExtension).error.log"
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
    lines.append("--- NSError 詳細 ---")
    let nsErr = error as NSError
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
            handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
        }
    } else {
        try? data.write(to: fileURL)
    }
}

// MARK: - 設定ストア

struct TestAppSettings: Codable, Equatable {
    var region: String = "ap-northeast-1"
    var bedrockModelId: String = "anthropic.claude-sonnet-4-6"
    var summaryAdditionalPrompt: String = ""
}

final class TestSettingsStore {
    private let fileURL: URL
    init(directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        self.fileURL = directory.appendingPathComponent("settings.json")
    }
    func load() -> TestAppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(TestAppSettings.self, from: data)
        else { return TestAppSettings() }
        return s
    }
    func save(_ s: TestAppSettings) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: fileURL, options: .atomic)
    }
}

// MARK: - テスト実行

print("\n🧪 ErrorLogger テスト")
print("  テストデータ: \(testDataDir.path)\n")

test("元ファイル名ベースのエラーログが生成される") {
    cleanup(["test.error.log"])
    defer { cleanup(["test.error.log"]) }

    let error = NSError(domain: "TestDomain", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "テストエラー"])
    writeErrorLog(error: error, operation: "文字起こし", sourceFileName: "test.m4a", to: testDataDir)

    let logFile = testDataDir.appendingPathComponent("test.error.log")
    try assertTrue(FileManager.default.fileExists(atPath: logFile.path), "test.error.log が生成されていない")

    let content = try String(contentsOf: logFile, encoding: .utf8)
    try assertTrue(content.contains("エラーレポート"), "エラーレポートヘッダーがない")
    try assertTrue(content.contains("日時:"), "日時がない")
    try assertTrue(content.contains("操作: 文字起こし"), "操作名がない")
    try assertTrue(content.contains("処理ファイル: test.m4a"), "処理ファイル名がない")
    try assertTrue(content.contains("テストエラー"), "エラーメッセージがない")
    try assertTrue(content.contains("システム情報"), "システム情報がない")
}

test("ファイル名なしの場合は app.error.log に出力される") {
    cleanup(["app.error.log"])
    defer { cleanup(["app.error.log"]) }

    let error = NSError(domain: "TestDomain", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "ファイル名なしエラー"])
    writeErrorLog(error: error, operation: "不明な操作", sourceFileName: nil, to: testDataDir)

    let logFile = testDataDir.appendingPathComponent("app.error.log")
    try assertTrue(FileManager.default.fileExists(atPath: logFile.path), "app.error.log が生成されていない")

    let content = try String(contentsOf: logFile, encoding: .utf8)
    try assertTrue(content.contains("処理ファイル: (なし)"), "処理ファイル (なし) がない")
    try assertTrue(content.contains("操作: 不明な操作"), "操作名がない")
}

test("既存ファイルに追記される") {
    cleanup(["append_test.error.log"])
    defer { cleanup(["append_test.error.log"]) }

    let e1 = NSError(domain: "T", code: -1, userInfo: [NSLocalizedDescriptionKey: "エラー1"])
    let e2 = NSError(domain: "T", code: -2, userInfo: [NSLocalizedDescriptionKey: "エラー2"])
    writeErrorLog(error: e1, operation: "操作1", sourceFileName: "append_test.m4a", to: testDataDir)
    writeErrorLog(error: e2, operation: "操作2", sourceFileName: "append_test.m4a", to: testDataDir)

    let content = try String(contentsOf: testDataDir.appendingPathComponent("append_test.error.log"), encoding: .utf8)
    try assertTrue(content.contains("エラー1"), "エラー1 がない")
    try assertTrue(content.contains("エラー2"), "エラー2 がない")
    try assertTrue(content.contains("操作1"), "操作1 がない")
    try assertTrue(content.contains("操作2"), "操作2 がない")
}

test("テスト用音声ファイル (test.m4a) が存在する") {
    try assertTrue(FileManager.default.fileExists(atPath: testDataDir.appendingPathComponent("test.m4a").path),
                   "test/data/test.m4a が存在しません")
}

test("テスト用文字起こしテキストが存在する") {
    let file = testDataDir.appendingPathComponent("test.transcript.txt")
    try assertTrue(FileManager.default.fileExists(atPath: file.path),
                   "test/data/test.transcript.txt が存在しません")
    let text = try String(contentsOf: file, encoding: .utf8)
    try assertTrue(!text.isEmpty, "test.transcript.txt が空です")
}

print("\n🧪 追加プロンプト永続化テスト\n")

test("追加プロンプトが設定 JSON に保存・復元される") {
    let dir = testDataDir.appendingPathComponent("settings_test_\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = TestSettingsStore(directory: dir)
    try assertEqual(store.load().summaryAdditionalPrompt, "")

    var settings = store.load()
    settings.summaryAdditionalPrompt = "箇条書きで要約して"
    try store.save(settings)
    try assertEqual(store.load().summaryAdditionalPrompt, "箇条書きで要約して")
}

test("空文字の追加プロンプトも正しく保存・復元される") {
    let dir = testDataDir.appendingPathComponent("settings_empty_\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = TestSettingsStore(directory: dir)
    var settings = store.load()
    settings.summaryAdditionalPrompt = "テスト"
    try store.save(settings)
    settings.summaryAdditionalPrompt = ""
    try store.save(settings)
    try assertEqual(store.load().summaryAdditionalPrompt, "")
}

test("他の設定値に影響しない") {
    let dir = testDataDir.appendingPathComponent("settings_side_\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = TestSettingsStore(directory: dir)
    var settings = store.load()
    settings.region = "us-east-1"
    settings.bedrockModelId = "anthropic.claude-sonnet-4-6"
    settings.summaryAdditionalPrompt = "テストプロンプト"
    try store.save(settings)

    let r = store.load()
    try assertEqual(r.region, "us-east-1")
    try assertEqual(r.bedrockModelId, "anthropic.claude-sonnet-4-6")
    try assertEqual(r.summaryAdditionalPrompt, "テストプロンプト")
}

// MARK: - 結果

print("\n" + String(repeating: "─", count: 40))
print("結果: \(passedTests)/\(totalTests) テスト成功")
if !failedTests.isEmpty {
    print("\n失敗:")
    for (name, msg) in failedTests { print("  ❌ \(name): \(msg)") }
    exit(1)
}
print("✅ 全テスト成功\n")
