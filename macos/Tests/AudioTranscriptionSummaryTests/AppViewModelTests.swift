// AppViewModelTests.swift
// AppViewModel のユニットテスト
// 起動時の初期状態を検証する
// 要件: 6.4

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - テスト用モック群

/// FileImporting プロトコルに準拠したモック
private final class StubFileImporter: FileImporting, Sendable {
    static let supportedExtensions: Set<String> = ["m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"]

    func isSupported(fileExtension: String) -> Bool {
        Self.supportedExtensions.contains(fileExtension.lowercased())
    }

    func importFile(from url: URL) async throws -> AudioFile {
        throw AppError.corruptedFile
    }
}

/// Transcribing プロトコルに準拠したモック
private final class StubTranscriber: Transcribing, Sendable {
    func transcribe(
        audioFile: AudioFile,
        language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        throw AppError.silentAudio
    }

    func cancel() {}
}

/// Summarizing プロトコルに準拠したモック
private final class StubSummarizer: Summarizing, Sendable {
    static let minimumCharacterCount: Int = 50

    func summarize(transcript: Transcript) async throws -> Summary {
        throw AppError.insufficientContent(minimumCharacters: Self.minimumCharacterCount)
    }
}

/// AudioPlaying プロトコルに準拠したモック
private final class StubAudioPlayer: AudioPlaying {
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    func load(audioFile: AudioFile) throws {}
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(to time: TimeInterval) { currentTime = time }
}

/// Exporting プロトコルに準拠したモック
private final class StubExportManager: Exporting, Sendable {
    func canWrite(to directory: URL) -> Bool { true }

    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL {
        throw AppError.exportFailed(
            underlying: NSError(domain: "Test", code: -1, userInfo: nil)
        )
    }
}

// MARK: - 起動時の初期状態テスト（要件 6.4）

@Suite("AppViewModel 初期状態テスト")
struct AppViewModelInitialStateTests {

    /// AppViewModel の初期状態がすべてデフォルト値であることを確認
    @Test @MainActor func initialState() {
        let viewModel = AppViewModel(
            fileImporter: StubFileImporter(),
            transcriber: StubTranscriber(),
            summarizer: StubSummarizer(),
            audioPlayer: StubAudioPlayer(),
            exportManager: StubExportManager()
        )

        // audioFile が nil であること
        #expect(viewModel.audioFile == nil)

        // transcript が nil であること
        #expect(viewModel.transcript == nil)

        // summary が nil であること
        #expect(viewModel.summary == nil)

        // transcriptionProgress が 0 であること
        #expect(viewModel.transcriptionProgress == 0)

        // isSummarizing が false であること
        #expect(viewModel.isSummarizing == false)

        // errorMessage が nil であること
        #expect(viewModel.errorMessage == nil)

        // isPlaying が false であること
        #expect(viewModel.isPlaying == false)

        // playbackPosition が 0 であること
        #expect(viewModel.playbackPosition == 0)
    }
}
