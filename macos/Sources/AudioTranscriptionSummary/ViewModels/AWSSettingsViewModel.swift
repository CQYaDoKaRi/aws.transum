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

    /// AWS 接続済みかどうか（メイン画面の機能有効/無効判定用）
    var isAWSConnected: Bool {
        if connectionTestSuccess { return true }
        // SSO 認証済みで一時認証情報が有効な場合も接続済みとみなす
        if authMethod == .sso,
           ssoAuthService.loginState == .authenticated,
           let creds = SSOAuthService.cachedCredentials,
           creds.expiration > Date() {
            return true
        }
        return false
    }

    /// SSO 残り有効時間（分）。SSO以外またはcredsなしの場合はnil
    var ssoRemainingMinutes: Int? {
        guard authMethod == .sso,
              let creds = SSOAuthService.cachedCredentials else { return nil }
        let remaining = creds.expiration.timeIntervalSinceNow
        return remaining > 0 ? Int(remaining / 60) : nil
    }

    // MARK: - Published プロパティ（ディレクトリ設定）

    @Published var recordingDirectoryPath: String = ""
    @Published var exportDirectoryPath: String = ""

    // MARK: - Published プロパティ（リアルタイム設定）

    @Published var isRealtimeEnabled: Bool = true
    @Published var isAutoDetectEnabled: Bool = true
    @Published var defaultTargetLanguage: TranslationLanguage = .japanese
    @Published var bedrockModelId: String = "anthropic.claude-3-haiku-20240307-v1:0"

    // MARK: - Published プロパティ（認証方式）

    /// 現在の認証方式
    @Published var authMethod: AuthMethod = .sso
    /// 選択された AWS プロファイル名
    @Published var selectedProfileName: String = ""
    /// 利用可能なプロファイル一覧
    @Published var availableProfiles: [String] = []
    /// プロファイル読み込みエラー
    @Published var profileLoadError: String?

    // MARK: - Published プロパティ（SSO 設定）

    /// SSO Start URL
    @Published var ssoStartUrl: String = ""
    /// SSO リージョン
    @Published var ssoRegion: String = ""
    /// SSO で選択されたアカウント ID
    @Published var ssoAccountId: String = ""
    /// SSO で選択されたロール名
    @Published var ssoRoleName: String = ""
    /// SSO 認証サービス（共有インスタンス）
    var ssoAuthService: SSOAuthService { SSOAuthService.shared }

    // MARK: - Published プロパティ（S3 バケット選択）

    /// 利用可能な S3 バケット一覧
    @Published var availableBuckets: [String] = []
    /// バケット検索フィルター
    @Published var bucketSearchText: String = ""
    /// バケット一覧読み込み中
    @Published var isLoadingBuckets: Bool = false
    /// バケット読み込みエラー
    @Published var bucketLoadError: String?

    /// 検索フィルター適用後のバケット一覧
    var filteredBuckets: [String] {
        if bucketSearchText.isEmpty { return availableBuckets }
        return availableBuckets.filter { $0.localizedCaseInsensitiveContains(bucketSearchText) }
    }

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
    /// authMethod に応じて Access Key またはプロファイルから認証情報を解決する
    nonisolated static func loadAWSCredentials() -> AWSCredentials? {
        let settings = AppSettingsStore().load()
        let authMethod = AuthMethod(rawValue: settings.authMethod) ?? .sso

        switch authMethod {
        case .accessKey:
            let creds = AWSCredentials(
                accessKeyId: settings.accessKeyId,
                secretAccessKey: settings.secretAccessKey,
                region: settings.region
            )
            return creds.isValid ? creds : nil

        case .awsProfile:
            let profileName = settings.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !profileName.isEmpty else { return nil }
            do {
                let resolved = try AWSProfileCredentialHelper.resolveCredentials(profileName: profileName)
                let region = resolved.region ?? settings.region
                return AWSCredentials(
                    accessKeyId: resolved.accessKey,
                    secretAccessKey: resolved.secretKey,
                    region: region
                )
            } catch {
                // SSO プロファイル等: 静的キーがない場合は nil を返す
                // AWS_PROFILE 環境変数は resolveCredentials 内で設定済み
                return nil
            }

        case .sso:
            // SSO 方式: キャッシュされた一時認証情報を使用
            guard let creds = SSOAuthService.cachedCredentials,
                  creds.expiration > Date() else {
                return nil
            }
            return AWSCredentials(
                accessKeyId: creds.accessKeyId,
                secretAccessKey: creds.secretAccessKey,
                region: settings.region
            )
        }
    }

    /// JSON から S3 バケット名を読み込む
    nonisolated static func loadS3BucketName() -> String {
        AppSettingsStore().load().s3BucketName
    }

    /// AWS 認証情報が有効かどうか（authMethod に応じて判定）
    nonisolated static var hasValidCredentials: Bool {
        let settings = AppSettingsStore().load()
        let authMethod = AuthMethod(rawValue: settings.authMethod) ?? .sso

        switch authMethod {
        case .accessKey:
            return !settings.accessKeyId.isEmpty && !settings.secretAccessKey.isEmpty
        case .awsProfile:
            return !settings.awsProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sso:
            // SSO 方式: キャッシュされた一時認証情報が有効かどうか
            if let creds = SSOAuthService.cachedCredentials {
                return creds.expiration > Date()
            }
            return false
        }
    }

    /// AWS リージョン（static アクセス用）
    nonisolated static var currentRegion: String {
        AppSettingsStore().load().region
    }

    /// 要約に使用する Bedrock 基盤モデル ID
    nonisolated static var currentBedrockModelId: String {
        AppSettingsStore().load().bedrockModelId
    }

    // MARK: - 自動保存用 Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - イニシャライザ

    init() {
        loadAll()
        setupAutoSave()
    }

    /// 後方互換: credentialManager 引数は無視する
    init(credentialManager: any AWSCredentialManaging) {
        loadAll()
        setupAutoSave()
    }

    /// 設定変更時に即座に保存する（Combine で監視）
    private func setupAutoSave() {
        // 認証情報・ディレクトリ・リージョン・S3・モデル等の変更を監視
        Publishers.MergeMany(
            $accessKeyId.map { _ in () }.eraseToAnyPublisher(),
            $secretAccessKey.map { _ in () }.eraseToAnyPublisher(),
            $region.map { _ in () }.eraseToAnyPublisher(),
            $s3BucketName.map { _ in () }.eraseToAnyPublisher(),
            $recordingDirectoryPath.map { _ in () }.eraseToAnyPublisher(),
            $exportDirectoryPath.map { _ in () }.eraseToAnyPublisher(),
            $isRealtimeEnabled.map { _ in () }.eraseToAnyPublisher(),
            $bedrockModelId.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(8) // 初期値の発火をスキップ
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.saveToFile()
            // isSaved を更新
            if let self = self {
                self.updateSavedState()
            }
        }
        .store(in: &cancellables)

        // authMethod 変更時の処理（保存は保存ボタンで行う）
        $authMethod
            .dropFirst() // 初期値の発火をスキップ
            .sink { [weak self] newMethod in
                guard let self = self else { return }
                self.updateSavedState()
                // awsProfile に切り替わった時にプロファイル一覧を自動読み込み
                if newMethod == .awsProfile {
                    self.loadProfiles()
                }
            }
            .store(in: &cancellables)

        // selectedProfileName 変更時の処理
        $selectedProfileName
            .dropFirst() // 初期値の発火をスキップ
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.saveToFile()
                self.updateSavedState()
            }
            .store(in: &cancellables)

        // SSO 関連フィールド変更時の処理
        Publishers.MergeMany(
            $ssoStartUrl.map { _ in () }.eraseToAnyPublisher(),
            $ssoRegion.map { _ in () }.eraseToAnyPublisher(),
            $ssoAccountId.map { _ in () }.eraseToAnyPublisher(),
            $ssoRoleName.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(4) // 初期値の発火をスキップ
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.saveToFile()
            self?.updateSavedState()
        }
        .store(in: &cancellables)
    }

    /// isSaved 状態を更新する
    private func updateSavedState() {
        switch authMethod {
        case .accessKey:
            isSaved = !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .awsProfile:
            isSaved = !selectedProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sso:
            // SSO 方式: Start URL が非空かつ認証済みの場合に保存済みとみなす
            isSaved = !ssoStartUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ssoAuthService.loginState == .authenticated
        }
    }

    // MARK: - 読み込み

    func loadAll() {
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
        bedrockModelId = settings.bedrockModelId

        // 認証方式の復元
        authMethod = AuthMethod(rawValue: settings.authMethod) ?? .sso
        selectedProfileName = settings.awsProfileName

        // SSO 設定の復元
        ssoStartUrl = settings.ssoStartUrl
        ssoRegion = settings.ssoRegion
        ssoAccountId = settings.ssoAccountId
        ssoRoleName = settings.ssoRoleName

        // isSaved の初期状態を authMethod に応じて設定
        switch authMethod {
        case .accessKey:
            isSaved = !settings.accessKeyId.isEmpty && !settings.secretAccessKey.isEmpty
        case .awsProfile:
            isSaved = !settings.awsProfileName.isEmpty
        case .sso:
            // SSO 方式: キャッシュから復元を試みる
            ssoAuthService.restoreFromCache()
            if ssoAuthService.loginState == .authenticated {
                isSaved = true
            } else {
                isSaved = false
            }
        }

        // awsProfile の場合はプロファイル一覧を読み込み
        if authMethod == .awsProfile {
            loadProfiles()
        }

        // 保存済みモデルがリージョンで利用不可、またはモデルリストに存在しない場合は自動切り替え
        let models = BedrockModel.availableModels(for: region)
        if BedrockModel.find(by: bedrockModelId) == nil || !models.contains(where: { $0.id == bedrockModelId }) {
            if let first = models.first {
                bedrockModelId = first.id
                // 修正した設定を直接ファイルに保存
                var fixedSettings = settings
                fixedSettings.bedrockModelId = first.id
                try? Self.settingsStore.save(fixedSettings)
            }
        }
    }

    // MARK: - JSON ファイルへの保存

    private func saveToFile() {
        var settings = AppSettings(
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            s3BucketName: s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines),
            recordingDirectoryPath: recordingDirectoryPath,
            exportDirectoryPath: exportDirectoryPath,
            isRealtimeEnabled: isRealtimeEnabled,
            isAutoDetectEnabled: isAutoDetectEnabled,
            defaultTargetLanguage: defaultTargetLanguage.rawValue,
            bedrockModelId: bedrockModelId
        )
        settings.authMethod = authMethod.rawValue
        settings.awsProfileName = selectedProfileName
        settings.ssoStartUrl = ssoStartUrl
        settings.ssoRegion = ssoRegion
        settings.ssoAccountId = ssoAccountId
        settings.ssoRoleName = ssoRoleName
        do {
            try Self.settingsStore.save(settings)
        } catch {
            // 保存失敗は致命的ではない
        }
    }

    // MARK: - 認証情報の操作

    func saveCredentials() {
        errorMessage = nil

        // 常に設定を保存する（接続テスト失敗でも保存は維持）
        saveToFile()

        // 認証方式ごとの必須項目チェック
        var hasValidationError = false
        switch authMethod {
        case .accessKey:
            if accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Access Key ID を入力してください"; hasValidationError = true
            } else if secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Secret Access Key を入力してください"; hasValidationError = true
            }
        case .awsProfile:
            if selectedProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "プロファイルを選択してください"; hasValidationError = true
            }
        case .sso:
            if ssoStartUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Start URL を入力してください"; hasValidationError = true
            } else if ssoRegion.isEmpty {
                errorMessage = "SSO リージョンを選択してください"; hasValidationError = true
            }
        }

        if s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "S3 バケット名を入力してください"; hasValidationError = true
        }

        isSaved = true

        // バリデーションエラーがなければ接続テストを実行
        if !hasValidationError {
            Task { await testConnection() }
        }
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

    // MARK: - 個別設定の保存

    /// リアルタイム文字起こし設定のみ保存する
    func saveRealtimeSetting() {
        saveToFile()
    }

    /// Bedrock 基盤モデル設定のみ保存する
    func saveBedrockModelSetting() {
        saveToFile()
    }

    // MARK: - プロファイル管理

    /// ~/.aws/config からプロファイル一覧を読み込む
    func loadProfiles() {
        profileLoadError = nil
        let configPath = AWSConfigParser.defaultConfigPath

        guard FileManager.default.fileExists(atPath: configPath) else {
            profileLoadError = "AWS CLI の設定ファイルが見つかりません"
            availableProfiles = []
            return
        }

        let profiles = AWSConfigParser.loadProfileNames(from: configPath)
        if profiles.isEmpty {
            profileLoadError = "プロファイルが見つかりません"
            availableProfiles = []
        } else {
            availableProfiles = profiles
            // 選択中のプロファイルが一覧にない場合は先頭を選択
            if !profiles.contains(selectedProfileName) && !profiles.isEmpty {
                selectedProfileName = profiles[0]
            }
        }
    }

    /// プロファイル一覧をリフレッシュする（リフレッシュボタン用）
    func refreshProfiles() {
        loadProfiles()
    }

    /// SSO 認証完了後に isSaved 状態を更新する（View から呼び出し用）
    func updateSSOSavedState() {
        updateSavedState()
        saveToFile()
    }

    // MARK: - S3 バケット一覧取得

    /// 選択中のリージョンの S3 バケット一覧を取得する
    func fetchBuckets() async {
        isLoadingBuckets = true
        bucketLoadError = nil
        availableBuckets = []

        do {
            let s3 = try AWSS3Service(region: region)
            let buckets = try await s3.listBuckets()
            availableBuckets = buckets.sorted()
        } catch {
            bucketLoadError = "バケット一覧の取得に失敗しました"
            availableBuckets = []
        }
        isLoadingBuckets = false
    }

    // MARK: - AWS 接続テスト

    func testConnection() async {
        connectionTestResult = nil
        connectionTestSuccess = false
        isTesting = true
        defer { isTesting = false }

        let bucket = s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bucket.isEmpty else {
            connectionTestResult = "S3 バケット名を入力してください。"; return
        }

        switch authMethod {
        case .accessKey:
            await testConnectionWithAccessKey(bucket: bucket)
        case .awsProfile:
            await testConnectionWithProfile(bucket: bucket)
        case .sso:
            await testConnectionWithSSO(bucket: bucket)
        }
    }

    /// Access Key 方式の接続テスト
    private func testConnectionWithAccessKey(bucket: String) async {
        let creds = AWSCredentials(
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard creds.isValid else {
            connectionTestResult = "認証情報を保存してください。"; return
        }

        do {
            let s3 = try AWSS3Service(credentials: creds)
            try await performS3ConnectionTest(s3: s3, bucket: bucket)
        } catch {
            handleConnectionTestError(error, bucket: bucket)
        }
    }

    /// AWS Profile 方式の接続テスト
    private func testConnectionWithProfile(bucket: String) async {
        guard !selectedProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            connectionTestResult = "プロファイルを選択してください。"; return
        }

        do {
            let s3 = try AWSS3Service()
            try await performS3ConnectionTest(s3: s3, bucket: bucket)
        } catch {
            // プロファイル認証失敗時の特別なメッセージ
            let d = error.localizedDescription.lowercased()
            if d.contains("expired") || d.contains("invalid") || d.contains("credential") {
                connectionTestResult = "接続失敗: 認証情報が無効です。`aws sso login --profile \(selectedProfileName)` を実行してください。"
                connectionTestSuccess = false
            } else {
                handleConnectionTestError(error, bucket: bucket)
            }
        }
    }

    /// SSO 方式の接続テスト
    private func testConnectionWithSSO(bucket: String) async {
        // SSO 認証が完了しているか確認
        guard ssoAuthService.loginState == .authenticated,
              SSOAuthService.cachedCredentials != nil else {
            connectionTestResult = "SSO ログインを実行してください。"
            connectionTestSuccess = false
            return
        }

        do {
            let s3 = try AWSS3Service()
            try await performS3ConnectionTest(s3: s3, bucket: bucket)
        } catch {
            let d = error.localizedDescription.lowercased()
            if d.contains("expired") || d.contains("token") {
                connectionTestResult = "接続失敗: 認証情報が期限切れです。設定画面から SSO ログインを再実行してください。"
                connectionTestSuccess = false
            } else {
                handleConnectionTestError(error, bucket: bucket)
            }
        }
    }

    /// S3 接続テストの共通処理
    private func performS3ConnectionTest(s3: AWSS3Service, bucket: String) async throws {
        let key = ".connection-test-\(UUID().uuidString)"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(key)
        try "test".data(using: .utf8)!.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await s3.putObject(bucket: bucket, key: key, fileURL: tmp)
        try await s3.deleteObject(bucket: bucket, key: key)
        connectionTestSuccess = true
        connectionTestResult = "接続成功: 認証情報と S3 バケットが正常に確認されました。"
    }

    /// 接続テストエラーの共通ハンドリング
    private func handleConnectionTestError(_ error: Error, bucket: String) {
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
