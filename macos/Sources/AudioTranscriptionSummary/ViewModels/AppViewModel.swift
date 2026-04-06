// AppViewModel.swift
// View と Service を接続する ViewModel
// 各サービスをプロトコル型で保持し、テスタビリティを確保する

import Foundation
import AVFoundation
import Combine

// MARK: - LastOperation（最後の操作コンテキスト）

/// 再試行メカニズム用の操作コンテキスト列挙型
/// エラー発生時に最後の操作を保持し、retry() で再実行可能にする
enum LastOperation: Sendable {
    /// ファイル読み込み操作
    case importFile(url: URL)
    /// 文字起こし操作
    case transcription(language: TranscriptionLanguage)
    /// 要約操作
    case summarization
    /// エクスポート操作
    case export(directory: URL)
}

// MARK: - AppViewModel

/// アプリケーション全体の状態管理と操作を担当する ViewModel
/// @MainActor により UI 更新をメインスレッドで安全に実行する
@MainActor
class AppViewModel: ObservableObject {

    // MARK: - Published プロパティ（UI バインディング用）

    /// 読み込まれた音声ファイル
    @Published var audioFile: AudioFile?
    /// 文字起こし結果
    @Published var transcript: Transcript?
    /// 要約結果
    @Published var summary: Summary?
    /// 文字起こしの進捗（0.0〜1.0）
    @Published var transcriptionProgress: Double = 0
    /// 文字起こし中かどうか
    @Published var isTranscribing: Bool = false
    /// 要約処理中かどうか
    @Published var isSummarizing: Bool = false
    /// エラーメッセージ（nil の場合はエラーなし）
    @Published var errorMessage: String?
    /// 再生中かどうか
    @Published var isPlaying: Bool = false
    /// 現在の再生位置（秒）
    @Published var playbackPosition: TimeInterval = 0

    // MARK: - サービス（プロトコル型で保持）
    // nonisolated(unsafe) により、@MainActor 隔離から nonisolated な
    // サービスメソッドへの送信を許可する（Swift 6 concurrency 対応）

    /// ファイル読み込みサービス
    nonisolated(unsafe) private let fileImporter: any FileImporting
    /// 文字起こしサービス
    nonisolated(unsafe) private let transcriber: any Transcribing
    /// 要約サービス
    nonisolated(unsafe) private let summarizer: any Summarizing
    /// 音声再生サービス
    nonisolated(unsafe) private let audioPlayer: any AudioPlaying
    /// エクスポートサービス
    nonisolated(unsafe) private let exportManager: any Exporting

    // MARK: - 再試行メカニズム

    /// 最後に実行した操作（再試行用）
    private(set) var lastOperation: LastOperation?

    // MARK: - システム音声キャプチャ

    /// システム音声キャプチャサービス
    nonisolated(unsafe) private let systemAudioCapture = SystemAudioCapture()

    /// 画面録画サービス
    nonisolated(unsafe) private let screenRecorder = ScreenRecorder()

    /// 動画から音声を抽出するサービス
    nonisolated(unsafe) private let audioExtractor = AudioExtractor()

    /// システム音声キャプチャ中かどうか
    @Published var isCapturingSystemAudio: Bool = false

    /// 画面録画中かどうか
    @Published var isRecordingScreen: Bool = false

    /// 音声抽出中かどうか（動画ファイルから音声を取り出し中）
    @Published var isExtractingAudio: Bool = false

    /// キャプチャ中の音声レベル（0.0〜1.0）
    @Published var captureAudioLevel: Float = 0

    /// 選択中の音源リソース
    @Published var selectedAudioSource: AudioSourceType = .systemAudio

    /// 利用可能な音源リソース一覧
    @Published var availableAudioSources: [AudioSourceType] = [.systemAudio]

    /// 最後にエクスポートした文字起こしファイルのパス
    @Published var lastTranscriptPath: String?

    /// 最後にエクスポートした要約ファイルのパス
    @Published var lastSummaryPath: String?

    /// 入力レベルプレビュー中かどうか
    @Published var isPreviewingLevel: Bool = false

    /// プレビュー用の入力レベル（0.0〜1.0）
    @Published var previewAudioLevel: Float = 0

    /// 画面録画中の音声レベル
    @Published var screenRecordingAudioLevel: Float = 0

    /// 画面録画のプレビューフレーム
    @Published var screenPreviewFrame: CGImage?

    /// プレビューフレーム更新タイマー
    nonisolated(unsafe) private var previewTimer: Timer?

    /// 変換処理のステータス
    enum ConvertingStatus: Equatable {
        case idle
        case saving       // RAW 保存中
        case converting   // 形式変換中
        case completed    // 完了
    }
    @Published var convertingStatus: ConvertingStatus = .idle

    // MARK: - 再生位置更新用タイマー

    /// 再生位置を定期更新するタイマー
    /// nonisolated(unsafe) により deinit からのアクセスを許可する
    nonisolated(unsafe) private var playbackTimer: Timer?

    // MARK: - イニシャライザ

    /// デフォルトでは具象クラスを使用するイニシャライザ
    /// テスト時にはモックを注入可能
    /// - Parameters:
    ///   - fileImporter: ファイル読み込みサービス（デフォルト: FileImporter）
    ///   - transcriber: 文字起こしサービス（デフォルト: Transcriber）
    ///   - summarizer: 要約サービス（デフォルト: Summarizer）
    ///   - audioPlayer: 音声再生サービス（デフォルト: AudioPlayerService）
    ///   - exportManager: エクスポートサービス（デフォルト: ExportManager）
    init(
        fileImporter: any FileImporting = FileImporter(),
        transcriber: any Transcribing = Transcriber(),
        summarizer: any Summarizing = Summarizer(),
        audioPlayer: any AudioPlaying = AudioPlayerService(),
        exportManager: any Exporting = ExportManager()
    ) {
        self.fileImporter = fileImporter
        self.transcriber = transcriber
        self.summarizer = summarizer
        self.audioPlayer = audioPlayer
        self.exportManager = exportManager
        // システム音声キャプチャのデリゲートを設定
        systemAudioCapture.delegate = self
        // 画面録画のデリゲートを設定
        screenRecorder.delegate = self
    }

    // MARK: - deinit

    deinit {
        playbackTimer?.invalidate()
    }

    // MARK: - ファイル読み込み

    /// 音声ファイルを読み込む
    /// FileImporter を呼び出し、成功時に audioFile を更新する
    /// - Parameter url: 読み込む音声ファイルの URL
    func importFile(from url: URL) async {
        // エラー状態をクリア
        errorMessage = nil
        lastOperation = .importFile(url: url)

        do {
            let file = try await fileImporter.importFile(from: url)

            // 動画ファイルの場合は音声を抽出する
            let mediaFile: AudioFile
            if FileImporter.videoExtensions.contains(file.fileExtension.lowercased()) {
                isExtractingAudio = true
                mediaFile = try await audioExtractor.extractAudio(from: file)
                isExtractingAudio = false
            } else {
                mediaFile = file
            }

            audioFile = mediaFile
            // 新しいファイル読み込み時に前の結果をクリア
            transcript = nil
            summary = nil
            transcriptionProgress = 0
            // 音声プレーヤーにファイルを読み込む
            try audioPlayer.load(audioFile: mediaFile)
            stopPlayback()
        } catch let error as AppError {
            isExtractingAudio = false
            errorMessage = error.errorDescription
        } catch {
            isExtractingAudio = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 文字起こし

    /// 文字起こしを開始する
    /// Transcriber を呼び出し、進捗を更新しながら文字起こしを実行する
    /// - Parameter language: 文字起こしに使用する言語
    func startTranscription(language: TranscriptionLanguage) async {
        guard audioFile != nil else { return }

        // 状態をリセット
        errorMessage = nil
        isTranscribing = true
        transcriptionProgress = 0
        transcript = nil
        summary = nil
        lastOperation = .transcription(language: language)

        do {
            let result = try await transcriber.transcribe(
                audioFile: audioFile!,
                language: language,
                onProgress: { [weak self] progress in
                    // 進捗コールバック（メインスレッドで更新）
                    Task { @MainActor [weak self] in
                        self?.transcriptionProgress = progress
                    }
                }
            )
            transcript = result
            transcriptionProgress = 1.0
        } catch let error as AppError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranscribing = false
    }

    // MARK: - 要約

    /// 追加プロンプト（要約時に使用）
    @Published var summaryAdditionalPrompt: String = ""

    /// 要約を開始する
    func startSummarization() async {
        guard let transcript = transcript else { return }
        errorMessage = nil
        isSummarizing = true
        summary = nil
        lastOperation = .summarization

        do {
            let result = try await summarizer.summarize(transcript: transcript, additionalPrompt: summaryAdditionalPrompt)
            summary = result
        } catch let error as AppError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isSummarizing = false
    }

    /// 要約のみ再実行する（文字起こし結果が既にある場合）
    func resummarize() async {
        guard transcript != nil else { return }
        await startSummarization()
    }

    // MARK: - 文字起こし + 要約 + 自動エクスポート（一括実行）

    // MARK: - 日時フォーマッター

    /// ファイル名に使用する日時フォーマッター（yyyyMMdd_HHmmss）
    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 文字起こし → 要約 → エクスポートを一括で実行する
    /// エクスポート先が設定済みの場合、日時ベースのファイル名で文字起こしと要約を別ファイルに保存する
    /// - Parameter language: 文字起こしに使用する言語
    func transcribeAndSummarize(language: TranscriptionLanguage) async {
        // 1. 文字起こし
        await startTranscription(language: language)
        guard transcript != nil, errorMessage == nil else { return }

        // 2. 要約
        await startSummarization()
        guard errorMessage == nil else { return }

        // 3. 自動エクスポート（エクスポート先が設定済みの場合）
        guard let exportDir = AWSSettingsViewModel.exportDirectory,
              let transcript = transcript else { return }

        // 元ファイル名をベースにする（例: system_audio_20260403_001508）
        let baseName = audioFile?.fileName ?? "transcript"

        do {
            // ディレクトリが存在しない場合は作成
            if !FileManager.default.fileExists(atPath: exportDir.path) {
                try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
            }

            // 文字起こし結果ファイル: 元ファイル名.transcript.txt
            let transcriptURL = exportDir.appendingPathComponent("\(baseName).transcript.txt")
            try transcript.text.write(to: transcriptURL, atomically: true, encoding: .utf8)
            lastTranscriptPath = transcriptURL.path

            // 要約結果ファイル: 元ファイル名.summary.txt
            if let summary = summary {
                let summaryURL = exportDir.appendingPathComponent("\(baseName).summary.txt")
                try summary.text.write(to: summaryURL, atomically: true, encoding: .utf8)
                lastSummaryPath = summaryURL.path
            }
        } catch {
            errorMessage = "エクスポートに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - エクスポート

    /// 結果をエクスポートする
    /// ExportManager を呼び出し、Transcript と Summary をファイルに保存する
    /// - Parameter directory: 保存先ディレクトリの URL
    func exportResults(to directory: URL) async {
        guard let transcript = transcript else { return }

        errorMessage = nil
        lastOperation = .export(directory: directory)

        do {
            _ = try await exportManager.export(
                transcript: transcript,
                summary: summary,
                to: directory
            )
        } catch let error as AppError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 再生制御

    /// 再生/一時停止をトグルする
    func togglePlayback() {
        guard audioFile != nil else { return }

        if audioPlayer.isPlaying {
            audioPlayer.pause()
            stopPlaybackTimer()
        } else {
            audioPlayer.play()
            startPlaybackTimer()
        }
        isPlaying = audioPlayer.isPlaying
    }

    /// 指定位置にシークする
    /// - Parameter time: シーク先の位置（秒）
    func seek(to time: TimeInterval) {
        audioPlayer.seek(to: time)
        playbackPosition = audioPlayer.currentTime
    }

    // MARK: - 再試行

    /// 最後の操作を再試行する
    /// lastOperation に保持された操作コンテキストに基づいて再実行する
    func retry() async {
        guard let operation = lastOperation else { return }

        switch operation {
        case .importFile(let url):
            await importFile(from: url)
        case .transcription(let language):
            await startTranscription(language: language)
        case .summarization:
            await startSummarization()
        case .export(let directory):
            await exportResults(to: directory)
        }
    }

    // MARK: - Private Methods（再生タイマー管理）

    /// 再生位置の定期更新タイマーを開始する
    /// 0.1秒間隔で再生位置を更新する
    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.playbackPosition = self.audioPlayer.currentTime
                self.isPlaying = self.audioPlayer.isPlaying
                // 再生が終了した場合はタイマーを停止
                if !self.audioPlayer.isPlaying {
                    self.stopPlaybackTimer()
                }
            }
        }
    }

    /// 再生位置の定期更新タイマーを停止する
    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// 再生状態を停止状態にリセットする
    private func stopPlayback() {
        audioPlayer.pause()
        stopPlaybackTimer()
        isPlaying = false
        playbackPosition = 0
    }

    // MARK: - システム音声キャプチャ

    /// 利用可能な音源リソースを更新する
    func refreshAudioSources() async {
        availableAudioSources = await AudioSourceProvider.availableSources()
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            await AVCaptureDevice.requestAccess(for: .audio)
            availableAudioSources = await AudioSourceProvider.availableSources()
        }
        await startLevelPreview()
    }

    /// 音源の入力レベルプレビューを開始する
    func startLevelPreview() async {
        await systemAudioCapture.stopMonitoring()
        previewAudioLevel = 0
        guard !selectedAudioSource.isScreenRecording, !isCapturingSystemAudio else { return }
        await systemAudioCapture.startMonitoring(sourceType: selectedAudioSource)
        isPreviewingLevel = true
    }

    /// 音源の入力レベルプレビューを停止する
    func stopLevelPreview() async {
        await systemAudioCapture.stopMonitoring()
        isPreviewingLevel = false
        previewAudioLevel = 0
    }

    /// リアルタイム文字起こし用の音声バッファ転送コールバックを設定する
    func setRealtimeAudioCallback(_ callback: (@Sendable (CMSampleBuffer) -> Void)?) {
        systemAudioCapture.onAudioBufferForRealtime = callback
    }

    /// システム音声のキャプチャを開始する（選択中の音源を使用）
    func startSystemAudioCapture() async {
        errorMessage = nil
        // ファイル選択をクリア
        audioFile = nil
        transcript = nil
        summary = nil
        transcriptionProgress = 0
        await stopLevelPreview()
        do {
            try await systemAudioCapture.startCapture(sourceType: selectedAudioSource)
            isCapturingSystemAudio = true
        } catch let error as AppError {
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録音に失敗しました")
        } catch {
            errorMessage = "録音の開始に失敗しました: \(error.localizedDescription)"
        }
    }

    /// システム音声のキャプチャを停止し、録音ファイルを保存する（文字起こしは自動実行しない）
    /// RAW 形式で保存（変換は一時的に無効）
    func stopSystemAudioCapture() async {
        convertingStatus = .saving
        do {
            isCapturingSystemAudio = false
            captureAudioLevel = 0

            let capturedFile = try await systemAudioCapture.stopCapture()

            audioFile = capturedFile
            transcript = nil
            summary = nil
            transcriptionProgress = 0

            // 音声プレーヤーへの読み込み（MOV の Float32 PCM は再生できない場合がある）
            do {
                try audioPlayer.load(audioFile: capturedFile)
            } catch {
                ErrorLogger.saveErrorLog(error: error, operation: "録音_プレーヤー読み込み",
                                         context: ["file": capturedFile.url.path,
                                                    "ext": capturedFile.fileExtension])
            }
            stopPlayback()
            convertingStatus = .completed

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.convertingStatus = .idle }
            }
        } catch let error as AppError {
            convertingStatus = .idle
            isCapturingSystemAudio = false
            captureAudioLevel = 0
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録音に失敗しました")
            ErrorLogger.saveErrorLog(error: error, operation: "録音保存",
                                     context: ["sourceType": "\(selectedAudioSource)"])
        } catch {
            convertingStatus = .idle
            isCapturingSystemAudio = false
            captureAudioLevel = 0
            errorMessage = "録音に失敗しました: \(error.localizedDescription)"
            ErrorLogger.saveErrorLog(error: error, operation: "録音保存",
                                     context: ["sourceType": "\(selectedAudioSource)"])
        }
    }

    /// システム音声のキャプチャをキャンセルする
    func cancelSystemAudioCapture() async {
        await systemAudioCapture.cancelCapture()
        isCapturingSystemAudio = false
        captureAudioLevel = 0
    }

    // MARK: - 画面録画

    /// 画面録画を開始する
    func startScreenRecording() async {
        errorMessage = nil
        // ファイル選択をクリア
        audioFile = nil
        transcript = nil
        summary = nil
        transcriptionProgress = 0
        screenRecorder.saveMode = .videoAndAudio
        do {
            try await screenRecorder.startRecording()
            isRecordingScreen = true
            // プレビューフレーム更新タイマー（0.1秒間隔）
            previewTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let frame = self.screenRecorder.latestPreviewFrame {
                        self.screenPreviewFrame = frame
                    }
                }
            }
        } catch let error as AppError {
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録画の開始に失敗しました")
        } catch {
            errorMessage = "録画の開始に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 画面録画を停止し、RAW 形式で保存する（変換は一時的に無効、文字起こしは自動実行しない）
    func stopScreenRecording() async {
        convertingStatus = .saving
        do {
            isRecordingScreen = false

            let capturedAudio = try await screenRecorder.stopRecording()

            audioFile = capturedAudio
            transcript = nil
            summary = nil
            transcriptionProgress = 0

            // 音声プレーヤーへの読み込み（MOV の Float32 PCM は再生できない場合がある）
            do {
                try audioPlayer.load(audioFile: capturedAudio)
            } catch {
                ErrorLogger.saveErrorLog(error: error, operation: "録画_プレーヤー読み込み",
                                         context: ["file": capturedAudio.url.path,
                                                    "ext": capturedAudio.fileExtension])
            }
            stopPlayback()
            convertingStatus = .completed

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.convertingStatus = .idle }
            }
        } catch let error as AppError {
            convertingStatus = .idle
            isRecordingScreen = false
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録画の保存に失敗しました")
            ErrorLogger.saveErrorLog(error: error, operation: "録画保存",
                                     context: ["saveMode": "videoAndAudio"])
        } catch {
            convertingStatus = .idle
            isRecordingScreen = false
            errorMessage = "録画の保存に失敗しました: \(error.localizedDescription)"
            ErrorLogger.saveErrorLog(error: error, operation: "録画保存",
                                     context: ["saveMode": "videoAndAudio"])
        }
    }

    /// 画面録画をキャンセルする
    func cancelScreenRecording() async {
        await screenRecorder.cancelRecording()
        isRecordingScreen = false
    }
}

// MARK: - SystemAudioCaptureDelegate

extension AppViewModel: SystemAudioCaptureDelegate {
    func captureDidStart() {
        isCapturingSystemAudio = true
    }

    func captureDidStop() {
        isCapturingSystemAudio = false
        captureAudioLevel = 0
    }

    func captureDidFail(with error: Error) {
        // モニタリング中（録音していない時）のエラーは無視
        guard isCapturingSystemAudio else { return }
        isCapturingSystemAudio = false
        captureAudioLevel = 0
        errorMessage = "システム音声キャプチャ中にエラーが発生しました: \(error.localizedDescription)"
    }

    func captureDidUpdateLevel(_ level: Float) {
        captureAudioLevel = level
        previewAudioLevel = level
    }
}

// MARK: - ScreenRecorderDelegate

extension AppViewModel: ScreenRecorderDelegate {
    func recorderDidStart() {
        isRecordingScreen = true
    }

    func recorderDidStop() {
        isRecordingScreen = false
        screenRecordingAudioLevel = 0
        screenPreviewFrame = nil
        previewTimer?.invalidate()
        previewTimer = nil
    }

    func recorderDidFail(with error: Error) {
        isRecordingScreen = false
        screenRecordingAudioLevel = 0
        errorMessage = "画面録画中にエラーが発生しました: \(error.localizedDescription)"
    }

    func recorderDidUpdateLevel(_ level: Float) {
        screenRecordingAudioLevel = level
    }
}
