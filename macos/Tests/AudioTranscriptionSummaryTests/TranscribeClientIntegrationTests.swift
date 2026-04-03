// TranscribeClientIntegrationTests.swift
// TranscribeClient を注入した AppViewModel の統合テスト
// 要約・エクスポート・再生が正常動作することを検証する
// 要件: 5.3

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - 統合テスト用モック群

/// AWSCredentialManaging のモック（認証情報を返却可能）
private final class IntegrationMockCredentialManager: AWSCredentialManaging, @unchecked Sendable {
    private var storedCredentials: AWSCredentials?

    init(credentials: AWSCredentials? = nil) {
        self.storedCredentials = credentials
    }

    func loadCredentials() -> AWSCredentials? { storedCredentials }
    func saveCredentials(_ credentials: AWSCredentials) throws { storedCredentials = credentials }
    func deleteCredentials() throws { storedCredentials = nil }
    var hasCredentials: Bool { storedCredentials != nil }
}

/// S3ClientProtocol のモック（常に成功）
private final class IntegrationMockS3Client: S3ClientProtocol, @unchecked Sendable {
    func putObject(bucket: String, key: String, fileURL: URL) async throws {}
    func deleteObject(bucket: String, key: String) async throws {}
}

/// TranscribeClientProtocol のモック（即座に完了を返す）
private final class IntegrationMockTranscribeService: TranscribeClientProtocol, @unchecked Sendable {
    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String {
        return "integration-test-job"
    }

    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus {
        return .completed(transcriptText: "統合テスト用の文字起こし結果テキスト")
    }
}

/// Summarizing のモック（正常に要約を返す）
private final class IntegrationMockSummarizer: Summarizing, Sendable {
    static let minimumCharacterCount: Int = 50

    func summarize(transcript: Transcript) async throws -> Summary {
        return Summary(
            id: UUID(),
            transcriptId: transcript.id,
            text: "要約: \(transcript.text.prefix(20))...",
            createdAt: Date()
        )
    }
}

/// Exporting のモック（正常にエクスポートを返す）
private final class IntegrationMockExportManager: Exporting, Sendable {
    func canWrite(to directory: URL) -> Bool { true }

    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL {
        return directory.appendingPathComponent("export.txt")
    }
}

/// AudioPlaying のモック（再生状態を管理）
private final class IntegrationMockAudioPlayer: AudioPlaying {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 60.0

    func load(audioFile: AudioFile) throws {}
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) { currentTime = time }
}

/// FileImporting のモック（正常にファイルを返す）
private final class IntegrationMockFileImporter: FileImporting, Sendable {
    static let supportedExtensions: Set<String> = ["m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"]

    func isSupported(fileExtension: String) -> Bool {
        Self.supportedExtensions.contains(fileExtension.lowercased())
    }

    func importFile(from url: URL) async throws -> AudioFile {
        return AudioFile(
            id: UUID(),
            url: url,
            fileName: "test-audio",
            fileExtension: "m4a",
            duration: 30.0,
            fileSize: 2048,
            createdAt: Date()
        )
    }
}

// MARK: - ヘルパー

/// TranscribeClient を transcriber として注入した AppViewModel を生成する
@MainActor
private func makeIntegrationViewModel(
    audioPlayer: IntegrationMockAudioPlayer = IntegrationMockAudioPlayer(),
    summarizer: IntegrationMockSummarizer = IntegrationMockSummarizer(),
    exportManager: IntegrationMockExportManager = IntegrationMockExportManager()
) -> AppViewModel {
    let credentials = AWSCredentials(
        accessKeyId: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG",
        region: "ap-northeast-1"
    )
    let transcribeClient = TranscribeClient(
        credentialManager: IntegrationMockCredentialManager(credentials: credentials),
        s3BucketName: "integration-test-bucket",
        s3Client: IntegrationMockS3Client(),
        transcribeClient: IntegrationMockTranscribeService(),
        pollingInterval: 1_000_000 // 1ms（テスト高速化）
    )

    return AppViewModel(
        fileImporter: IntegrationMockFileImporter(),
        transcriber: transcribeClient,
        summarizer: summarizer,
        audioPlayer: audioPlayer,
        exportManager: exportManager
    )
}

// MARK: - TranscribeClient 統合テスト（要件 5.3）

@Suite("TranscribeClient 統合テスト")
struct TranscribeClientIntegrationTests {

    // MARK: - 初期化テスト

    /// TranscribeClient を注入した AppViewModel が正常に初期化されることを確認
    @Test @MainActor func initializationWithTranscribeClient() {
        let viewModel = makeIntegrationViewModel()

        // 初期状態がデフォルト AppViewModel と同一であることを検証
        #expect(viewModel.audioFile == nil)
        #expect(viewModel.transcript == nil)
        #expect(viewModel.summary == nil)
        #expect(viewModel.transcriptionProgress == 0)
        #expect(viewModel.isSummarizing == false)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isPlaying == false)
        #expect(viewModel.playbackPosition == 0)
    }

    // MARK: - 要約の独立動作テスト

    /// TranscribeClient 注入時でも要約機能が正常に動作することを確認
    @Test @MainActor func summarizationWorksWithTranscribeClient() async {
        let viewModel = makeIntegrationViewModel()

        // 文字起こし結果を直接設定して要約をテスト
        let transcript = Transcript(
            id: UUID(),
            audioFileId: UUID(),
            text: String(repeating: "テスト文字起こしテキスト。", count: 10),
            language: .japanese,
            createdAt: Date()
        )
        viewModel.transcript = transcript

        await viewModel.startSummarization()

        // 要約が生成されていることを確認
        #expect(viewModel.summary != nil)
        #expect(viewModel.isSummarizing == false)
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - エクスポートの独立動作テスト

    /// TranscribeClient 注入時でもエクスポート機能が正常に動作することを確認
    @Test @MainActor func exportWorksWithTranscribeClient() async {
        let viewModel = makeIntegrationViewModel()

        // 文字起こし結果を設定
        let transcript = Transcript(
            id: UUID(),
            audioFileId: UUID(),
            text: "エクスポートテスト用テキスト",
            language: .japanese,
            createdAt: Date()
        )
        viewModel.transcript = transcript

        let tempDir = FileManager.default.temporaryDirectory
        await viewModel.exportResults(to: tempDir)

        // エラーが発生していないことを確認
        #expect(viewModel.errorMessage == nil)
    }

    // MARK: - 再生の独立動作テスト

    /// TranscribeClient 注入時でも再生制御が正常に動作することを確認
    @Test @MainActor func playbackWorksWithTranscribeClient() {
        let audioPlayer = IntegrationMockAudioPlayer()
        let viewModel = makeIntegrationViewModel(audioPlayer: audioPlayer)

        // AudioFile を設定（再生に必要）
        let audioFile = AudioFile(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test.m4a"),
            fileName: "test",
            fileExtension: "m4a",
            duration: 30.0,
            fileSize: 2048,
            createdAt: Date()
        )
        viewModel.audioFile = audioFile

        // 再生トグル
        viewModel.togglePlayback()
        #expect(viewModel.isPlaying == true)

        // 一時停止トグル
        viewModel.togglePlayback()
        #expect(viewModel.isPlaying == false)

        // シーク
        viewModel.seek(to: 15.0)
        #expect(viewModel.playbackPosition == 15.0)
    }
}
