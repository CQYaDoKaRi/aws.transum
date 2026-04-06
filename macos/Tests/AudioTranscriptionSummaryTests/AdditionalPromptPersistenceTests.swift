// AdditionalPromptPersistenceTests.swift
// 追加プロンプトの設定保存・復元テスト
// - 要約実行時に追加プロンプトが設定 JSON に保存されること
// - アプリ起動時（AppViewModel 初期化時）に復元されること

import Testing
import Foundation
@testable import AudioTranscriptionSummary

/// テストデータディレクトリのパス
private let testDataDir: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url = url.deletingLastPathComponent() }
    return url.appendingPathComponent("test/data")
}()

@Suite("追加プロンプト永続化テスト")
struct AdditionalPromptPersistenceTests {

    @Test("追加プロンプトが設定 JSON に保存・復元される")
    func testSaveAndRestore() throws {
        let settingsDir = testDataDir.appendingPathComponent("settings_test")
        let settingsFile = settingsDir.appendingPathComponent("settings.json")
        defer {
            try? FileManager.default.removeItem(at: settingsDir)
        }

        let store = AppSettingsStore(directory: settingsDir)

        // 初期状態: 空文字
        let initial = store.load()
        #expect(initial.summaryAdditionalPrompt == "")

        // 保存
        var settings = initial
        settings.summaryAdditionalPrompt = "箇条書きで要約して"
        try store.save(settings)

        // ファイルが生成されたことを確認
        #expect(FileManager.default.fileExists(atPath: settingsFile.path))

        // 復元
        let restored = store.load()
        #expect(restored.summaryAdditionalPrompt == "箇条書きで要約して")
    }

    @Test("空文字の追加プロンプトも正しく保存・復元される")
    func testEmptyPrompt() throws {
        let settingsDir = testDataDir.appendingPathComponent("settings_empty_test")
        defer {
            try? FileManager.default.removeItem(at: settingsDir)
        }

        let store = AppSettingsStore(directory: settingsDir)

        var settings = store.load()
        settings.summaryAdditionalPrompt = "テスト"
        try store.save(settings)

        // 空文字で上書き
        settings.summaryAdditionalPrompt = ""
        try store.save(settings)

        let restored = store.load()
        #expect(restored.summaryAdditionalPrompt == "")
    }

    @Test("他の設定値に影響しない")
    func testNoSideEffects() throws {
        let settingsDir = testDataDir.appendingPathComponent("settings_sideeffect_test")
        defer {
            try? FileManager.default.removeItem(at: settingsDir)
        }

        let store = AppSettingsStore(directory: settingsDir)

        var settings = store.load()
        settings.region = "us-east-1"
        settings.bedrockModelId = "anthropic.claude-sonnet-4-6"
        settings.summaryAdditionalPrompt = "テストプロンプト"
        try store.save(settings)

        let restored = store.load()
        #expect(restored.region == "us-east-1")
        #expect(restored.bedrockModelId == "anthropic.claude-sonnet-4-6")
        #expect(restored.summaryAdditionalPrompt == "テストプロンプト")
    }
}
