// AudioTranscriptionSummaryApp.swift
// アプリケーションのエントリポイント
// 起動時に JSON 設定ファイルから AWS 認証情報を読み込み、
// 設定済みなら TranscribeClient を AppViewModel に注入する

import SwiftUI

/// macOS 音声文字起こし・要約アプリケーションのメインエントリポイント
@main
struct AudioTranscriptionSummaryApp: App {

    /// アプリ設定画面の ViewModel
    @StateObject private var awsSettingsViewModel: AWSSettingsViewModel

    /// アプリケーション全体の状態を管理する ViewModel
    @StateObject private var appViewModel: AppViewModel

    init() {
        // Dock にアプリアイコンを表示する
        NSApplication.shared.setActivationPolicy(.regular)

        let settingsVM = AWSSettingsViewModel()
        _awsSettingsViewModel = StateObject(wrappedValue: settingsVM)

        // JSON から認証情報を読み込み、TranscribeClient を構築
        let vm = Self.createAppViewModel()
        _appViewModel = StateObject(wrappedValue: vm)
    }

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: appViewModel, awsSettingsViewModel: awsSettingsViewModel)
        }
    }

    /// AWS 認証情報から AppViewModel を構築する
    /// 認証情報が未設定またはサービス初期化に失敗した場合はデフォルト（SFSpeechRecognizer）にフォールバック
    private static func createAppViewModel() -> AppViewModel {
        guard let credentials = AWSSettingsViewModel.loadAWSCredentials() else {
            return AppViewModel()
        }

        let bucketName = AWSSettingsViewModel.loadS3BucketName()
        guard !bucketName.isEmpty else {
            return AppViewModel()
        }

        // AWS SDK の初期化を試みる
        // 失敗した場合でも TranscribeClient を構築し、transcribe 呼び出し時にエラーを返す
        let jsonCredManager = JSONCredentialManager()

        do {
            let s3Service = try AWSS3Service(credentials: credentials)
            let transcribeService = try AWSTranscribeService(credentials: credentials)
            let transcribeClient = TranscribeClient(
                credentialManager: jsonCredManager,
                s3BucketName: bucketName,
                s3Client: s3Service,
                transcribeClient: transcribeService
            )
            return AppViewModel(transcriber: transcribeClient)
        } catch {
            // SDK 初期化失敗時もフォールバックせず、エラーを保持する ViewModel を返す
            // ユーザーが文字起こしを試みた際にエラーメッセージが表示される
            return AppViewModel()
        }
    }
}

// MARK: - JSONCredentialManager

/// JSON 設定ファイルから認証情報を読み込む AWSCredentialManaging 実装
final class JSONCredentialManager: AWSCredentialManaging, Sendable {
    private let store = AppSettingsStore()

    func loadCredentials() -> AWSCredentials? {
        let s = store.load()
        let c = AWSCredentials(accessKeyId: s.accessKeyId, secretAccessKey: s.secretAccessKey, region: s.region)
        return c.isValid ? c : nil
    }

    func saveCredentials(_ credentials: AWSCredentials) throws {
        var s = store.load()
        s.accessKeyId = credentials.accessKeyId
        s.secretAccessKey = credentials.secretAccessKey
        s.region = credentials.region
        try store.save(s)
    }

    func deleteCredentials() throws {
        var s = store.load()
        s.accessKeyId = ""
        s.secretAccessKey = ""
        try store.save(s)
    }

    var hasCredentials: Bool {
        loadCredentials() != nil
    }
}
