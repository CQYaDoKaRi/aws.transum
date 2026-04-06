// AppSettingsStore.swift
// アプリ設定を JSON ファイルに永続化するサービス
// ~/Library/Application Support/AudioTranscriptionSummary/settings.json に保存する

import Foundation

// MARK: - AppSettings（設定データモデル）

/// JSON ファイルに保存するアプリ設定（AWS 認証情報を含む）
struct AppSettings: Codable, Equatable {
    /// AWS Access Key ID
    var accessKeyId: String = ""
    /// AWS Secret Access Key
    var secretAccessKey: String = ""
    /// AWS リージョン
    var region: String = "ap-northeast-1"
    /// S3 バケット名
    var s3BucketName: String = ""
    /// 録音データの保存先ディレクトリパス（空の場合はシステム一時ディレクトリ）
    var recordingDirectoryPath: String = ""
    /// エクスポートデータの保存先ディレクトリパス（空の場合は毎回ダイアログで選択）
    var exportDirectoryPath: String = ""
    /// リアルタイム文字起こしの有効/無効
    var isRealtimeEnabled: Bool = true
    /// 言語自動判別の有効/無効
    var isAutoDetectEnabled: Bool = true
    /// デフォルト翻訳先言語コード
    var defaultTargetLanguage: String = "ja"
    /// 要約に使用する Bedrock 基盤モデル ID
    var bedrockModelId: String = "anthropic.claude-sonnet-4-6"
}

// MARK: - AppSettingsStore（設定ファイル管理）

/// アプリ設定を JSON ファイルで管理するクラス
/// スレッドセーフな読み書きを提供する
final class AppSettingsStore: Sendable {

    /// 設定ファイルの保存先ディレクトリ
    private let directoryURL: URL

    /// 設定ファイルのパス
    private let fileURL: URL

    /// JSON エンコーダー（整形出力）
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    // MARK: - 初期化

    /// デフォルトの保存先（~/Library/Application Support/AudioTranscriptionSummary/）で初期化
    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.directoryURL = appSupport.appendingPathComponent("AudioTranscriptionSummary")
        self.fileURL = directoryURL.appendingPathComponent("settings.json")
    }

    /// テスト用: 任意のディレクトリを指定して初期化
    init(directory: URL) {
        self.directoryURL = directory
        self.fileURL = directory.appendingPathComponent("settings.json")
    }

    // MARK: - 読み込み

    /// 設定ファイルから設定を読み込む
    /// ファイルが存在しない場合はデフォルト値を返す
    func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // パース失敗時はデフォルト値を返す
            return AppSettings()
        }
    }

    // MARK: - 保存

    /// 設定を JSON ファイルに保存する
    /// - Parameter settings: 保存する設定
    /// - Throws: ディレクトリ作成またはファイル書き込みに失敗した場合
    func save(_ settings: AppSettings) throws {
        // ディレクトリが存在しない場合は作成
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
        }
        let data = try Self.encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 設定ファイルパス

    /// 設定ファイルの絶対パスを返す
    var settingsFilePath: String {
        fileURL.path
    }
}
