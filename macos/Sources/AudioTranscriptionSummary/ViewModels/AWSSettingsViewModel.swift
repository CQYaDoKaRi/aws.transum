// AWSSettingsViewModel.swift
// アプリ設定画面の ViewModel
// 全設定を JSON ファイル（settings.json）に永続化する

import Foundation
import Combine
import AppKit

// MARK: - AWSSettingsViewModel（アプリ設定画面 ViewModel）

/// AWS 認証情報とアプリ設定を管理する ViewModel
/// 全設定を ~/Library/Application Support/AudioTranscriptionSummary/settings.json に保存する
@MainActor
class AWSSettingsViewModel: ObservableObject {

    // MARK: - Published プロパティ（AWS 認証情報）

    @Published var accessKeyId: String = ""
    @Published var secretAccessKey: String = ""
    @Published var region: String = "ap-northeast-1"
    @Published var s3BucketName: String = ""
    @Published var isSaved: Bool = false
    @Published var errorMessage: String?
    @Published var isTesting: Bool = false
    @Published var connectionTestResult: String?
    @Published var connectionTestSuccess: Bool = false

    // MARK: - Published プロパティ（ディレクトリ設定）

    @Published var recordingDirectoryPath: String = ""
    @Published var exportDirectoryPath: String = ""

    // MARK: - Published プロパティ（リアルタイム設定）

    @Published var isRealtimeEnabled: Bool = true
    @Published var isAutoDetectEnabled: Bool = true
    @Published var defaultTargetLanguage: TranslationLanguage = .japanese

    // MARK: - 設定ファイルストア

    nonisolated(unsafe) private static let settingsStore = AppSettingsStore()

    // MARK: - 静的プロパティ

    /// 録音データの保存先ディレクトリ
    nonisolated static var recordingDirectory: URL {
        let settings = AppSettingsStore().load()
        if !settings.recordingDirectoryPath.isEmpty {
            let url = URL(fileURLWithPath: settings.recordingDirectoryPath)
            if FileManager.default.isWritableFile(atPath: settings.recordingDirectoryPath) {
                return url
            }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            } catch {}
        }
        return FileManager.default.temporaryDirectory
    }

    /// エクスポートデータの保存先ディレクトリ（未設定時は nil）
    nonisolated static var exportDirectory: URL? {
        let settings = AppSettingsStore().load()
        if !settings.exportDirectoryPath.isEmpty {
            let url = URL(fileURLWithPath: settings.exportDirectoryPath)
            if FileManager.default.isWritableFile(atPath: settings.exportDirectoryPath) {
                return url
            }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                return url
            } catch {}
        }
        return nil
    }

    /// JSON から AWS 認証情報を読み込む（アプリ起動時の DI 用）
    nonisolated static func loadAWSCredentials() -> AWSCredentials? {
        let settings = AppSettingsStore().load()
        let creds = AWSCredentials(
            accessKeyId: settings.accessKeyId,
            secretAccessKey: settings.secretAccessKey,
            region: settings.region
        )
        return creds.isValid ? creds : nil
    }

    /// JSON から S3 バケット名を読み込む
    nonisolated static func loadS3BucketName() -> String {
        AppSettingsStore().load().s3BucketName
    }

    /// AWS 認証情報が有効かどうか
    nonisolated static var hasValidCredentials: Bool {
        let settings = AppSettingsStore().load()
        return !settings.accessKeyId.isEmpty && !settings.secretAccessKey.isEmpty
    }

    /// AWS リージョン（static アクセス用）
    nonisolated static var currentRegion: String {
        AppSettingsStore().load().region
    }

    // MARK: - イニシャライザ

    init() {
        loadAll()
    }

    /// 後方互換: credentialManager 引数は無視する
    init(credentialManager: any AWSCredentialManaging) {
        loadAll()
    }

    // MARK: - 読み込み

    private func loadAll() {
        let settings = Self.settingsStore.load()
        accessKeyId = settings.accessKeyId
        secretAccessKey = settings.secretAccessKey
        region = settings.region
        s3BucketName = settings.s3BucketName
        recordingDirectoryPath = settings.recordingDirectoryPath
        exportDirectoryPath = settings.exportDirectoryPath
        isRealtimeEnabled = settings.isRealtimeEnabled
        isAutoDetectEnabled = settings.isAutoDetectEnabled
        defaultTargetLanguage = TranslationLanguage(rawValue: settings.defaultTargetLanguage) ?? .japanese
        isSaved = !settings.accessKeyId.isEmpty && !settings.secretAccessKey.isEmpty
    }

    // MARK: - JSON ファイルへの保存

    private func saveToFile() {
        let settings = AppSettings(
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            s3BucketName: s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
            recordingDirectoryPath: recordingDirectoryPath,
            exportDirectoryPath: exportDirectoryPath,
            isRealtimeEnabled: isRealtimeEnabled,
            isAutoDetectEnabled: isAutoDetectEnabled,
            defaultTargetLanguage: defaultTargetLanguage.rawValue
        )
        do {
            try Self.settingsStore.save(settings)
        } catch {
            // 保存失敗は致命的ではない
        }
    }

    // MARK: - 認証情報の操作

    func saveCredentials() {
        errorMessage = nil

        guard !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Access Key ID を入力してください"; return
        }
        guard !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Secret Access Key を入力してください"; return
        }
        guard !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "リージョンを入力してください"; return
        }
        guard !s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "S3 バケット名を入力してください"; return
        }

        saveToFile()
        isSaved = true
    }

    func deleteCredentials() {
        errorMessage = nil
        accessKeyId = ""
        secretAccessKey = ""
        region = "ap-northeast-1"
        s3BucketName = ""
        isSaved = false
        saveToFile()
    }

    // MARK: - 録音データ保存先

    func chooseRecordingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "録音データの保存先を選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recordingDirectoryPath = url.path
        saveToFile()
    }

    func resetRecordingDirectory() {
        recordingDirectoryPath = ""
        saveToFile()
    }

    // MARK: - エクスポートデータ保存先

    func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.title = "エクスポート先フォルダを選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportDirectoryPath = url.path
        saveToFile()
    }

    func resetExportDirectory() {
        exportDirectoryPath = ""
        saveToFile()
    }

    // MARK: - AWS 接続テスト

    func testConnection() async {
        connectionTestResult = nil
        connectionTestSuccess = false
        isTesting = true
        defer { isTesting = false }

        let creds = AWSCredentials(
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard creds.isValid else {
            connectionTestResult = "認証情報を保存してください。"; return
        }
        let bucket = s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty else {
            connectionTestResult = "S3 バケット名を入力してください。"; return
        }

        do {
            let s3 = try AWSS3Service(credentials: creds)
            let key = ".connection-test-\(UUID().uuidString)"
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(key)
            try "test".data(using: .utf8)!.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await s3.putObject(bucket: bucket, key: key, fileURL: tmp)
            try await s3.deleteObject(bucket: bucket, key: key)
            connectionTestSuccess = true
            connectionTestResult = "接続成功: 認証情報と S3 バケットが正常に確認されました。"
        } catch {
            connectionTestSuccess = false
            let d = error.localizedDescription.lowercased()
            if d.contains("access denied") || d.contains("forbidden") {
                connectionTestResult = "接続失敗: S3 バケットへのアクセス権限がありません。IAM ポリシーを確認してください。"
            } else if d.contains("no such bucket") || d.contains("nosuchbucket") {
                connectionTestResult = "接続失敗: S3 バケット「\(bucket)」が見つかりません。"
            } else if (error as NSError).domain == NSURLErrorDomain {
                connectionTestResult = "接続失敗: ネットワーク接続を確認してください。"
            } else {
                connectionTestResult = "接続失敗: \(error.localizedDescription)"
            }
        }
    }
}
