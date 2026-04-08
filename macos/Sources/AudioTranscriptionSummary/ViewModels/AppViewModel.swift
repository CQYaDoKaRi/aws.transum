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

    // MARK: - ファイル分割設定

    /// ファイル分割間隔（分）。1〜60、デフォルト30分
    @Published var splitIntervalMinutes: Int = 30

    // MARK: - ファイルリスト（複数ファイル文字起こし用）

    /// 音声文字起こし用のファイルリスト
    @Published var fileList: [FileListItem] = []

    /// 全ファイルが選択されているかどうか
    var isAllSelected: Bool {
        !fileList.isEmpty && fileList.allSatisfy { $0.isSelected }
    }
    /// 波形描画用データ（0.0〜1.0 の正規化された振幅値）
    @Published var waveformData: [Float] = []

    /// 処理中かどうか（文字起こしまたは要約のいずれかが実行中）
    var isProcessing: Bool {
        isTranscribing || isSummarizing
    }

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

    /// 録音開始中フラグ（ボタン無効化用）
    @Published var isStartingCapture: Bool = false

    /// 録音停止中フラグ（ボタン無効化用）
    @Published var isStoppingCapture: Bool = false

    /// ステータスバー用の進捗値（0.0〜1.0、nil の場合は不定プログレス）
    var statusProgress: Double? {
        if isTranscribing { return transcriptionProgress }
        if isSummarizing || isCapturingSystemAudio || isRecordingScreen || isExtractingAudio { return nil }
        return nil
    }

    /// ステータスバー用の進捗メッセージ
    var statusMessage: String? {
        if isStartingCapture { return "録音開始中..." }
        if isStoppingCapture { return "録音停止中..." }
        if isExtractingAudio { return "音声を抽出中..." }
        if isTranscribing { return "文字起こし中... \(Int(transcriptionProgress * 100))%" }
        if isSummarizing { return "要約を生成中..." }
        if isCapturingSystemAudio { return "システム音声をキャプチャ中..." }
        if isRecordingScreen { return "画面録画中..." }
        return nil
    }

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
        // 分割ファイル確定時にファイルリストへ自動登録
        systemAudioCapture.onFileSplitCompleted = { [weak self] file in
            guard let self = self else { return }
            let item = FileListItem(id: UUID(), audioFile: file, isSelected: true)
            self.fileList.append(item)
        }
        // 画面録画のデリゲートを設定
        screenRecorder.delegate = self
        // 追加プロンプトを設定から復元
        summaryAdditionalPrompt = AppSettingsStore().load().summaryAdditionalPrompt
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
            // 波形データを生成
            waveformData = WaveformDataProvider.loadWaveformData(from: mediaFile.url)
            // 音声プレーヤーにファイルを読み込む
            try audioPlayer.load(audioFile: mediaFile)
            stopPlayback()
        } catch let error as AppError {
            isExtractingAudio = false
            errorMessage = error.errorDescription
            ErrorLogger.saveErrorLog(error: error, operation: "ファイル読み込み", sourceFileName: url.lastPathComponent)
        } catch {
            isExtractingAudio = false
            errorMessage = error.localizedDescription
            ErrorLogger.saveErrorLog(error: error, operation: "ファイル読み込み", sourceFileName: url.lastPathComponent)
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
            ErrorLogger.saveErrorLog(error: error, operation: "文字起こし", sourceFileName: audioFile?.fileName)
        } catch {
            errorMessage = error.localizedDescription
            ErrorLogger.saveErrorLog(error: error, operation: "文字起こし", sourceFileName: audioFile?.fileName)
        }

        isTranscribing = false
    }

    // MARK: - 要約

    /// 追加プロンプト（要約時に使用）
    @Published var summaryAdditionalPrompt: String = ""

    /// 設定で選択されている Bedrock 基盤モデル ID
    var awsSettingsBedrockModelId: String {
        AWSSettingsViewModel.currentBedrockModelId
    }

    /// 要約を開始する
    func startSummarization() async {
        guard let transcript = transcript else { return }
        errorMessage = nil
        isSummarizing = true
        summary = nil
        lastOperation = .summarization

        // 追加プロンプトを設定に保存
        let store = AppSettingsStore()
        var settings = store.load()
        settings.summaryAdditionalPrompt = summaryAdditionalPrompt
        try? store.save(settings)

        do {
            let result = try await summarizer.summarize(transcript: transcript, additionalPrompt: summaryAdditionalPrompt)
            summary = result
        } catch let error as AppError {
            errorMessage = error.errorDescription
            ErrorLogger.saveErrorLog(error: error, operation: "要約", sourceFileName: audioFile?.fileName)
        } catch {
            errorMessage = error.localizedDescription
            ErrorLogger.saveErrorLog(error: error, operation: "要約", sourceFileName: audioFile?.fileName)
        }
        isSummarizing = false
    }

    /// 要約のみ再実行する（文字起こし結果が既にある場合）
    /// 追加プロンプトを参照し、要約結果をファイルにも保存する
    func resummarize() async {
        guard transcript != nil else { return }
        await startSummarization()

        // 要約結果をファイルに保存（エクスポート先が設定済みの場合）
        if let exportDir = AWSSettingsViewModel.exportDirectory, let summary = summary {
            let baseName = audioFile?.fileName ?? "transcript"
            let summaryURL = exportDir.appendingPathComponent("\(baseName).summary.txt")
            do {
                if !FileManager.default.fileExists(atPath: exportDir.path) {
                    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
                }
                try summary.text.write(to: summaryURL, atomically: true, encoding: .utf8)
                lastSummaryPath = summaryURL.path
            } catch {
                errorMessage = "要約ファイルの保存に失敗しました: \(error.localizedDescription)"
                ErrorLogger.saveErrorLog(error: error, operation: "要約ファイル保存", sourceFileName: audioFile?.fileName)
            }
        }
    }

    /// テキストファイルを読み込んで要約する
    func summarizeFromFile(url: URL) async {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "ファイルが空です"
                return
            }
            let tempTranscript = Transcript(
                id: UUID(),
                audioFileId: audioFile?.id ?? UUID(),
                text: text,
                language: .auto,
                createdAt: Date()
            )
            transcript = tempTranscript
            await startSummarization()

            // 要約結果をファイルに保存
            if let exportDir = AWSSettingsViewModel.exportDirectory, let summary = summary {
                let baseName = url.deletingPathExtension().lastPathComponent
                let summaryURL = exportDir.appendingPathComponent("\(baseName).summary.txt")
                if !FileManager.default.fileExists(atPath: exportDir.path) {
                    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
                }
                try summary.text.write(to: summaryURL, atomically: true, encoding: .utf8)
                lastSummaryPath = summaryURL.path
            }
        } catch {
            errorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
            ErrorLogger.saveErrorLog(error: error, operation: "ファイルから要約", sourceFileName: url.lastPathComponent)
        }
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
            ErrorLogger.saveErrorLog(error: error, operation: "自動エクスポート", sourceFileName: audioFile?.fileName)
        }
    }

    // MARK: - ファイルリスト操作

    /// ファイルリストにファイルを追加する
    /// FileImporter で各 URL を読み込み、FileListItem として末尾に追加する
    /// サポート対象外・破損ファイルはスキップし errorMessage に記録する
    /// - Parameter urls: 追加するファイルの URL 配列
    func addFilesToList(_ urls: [URL]) async {
        var errors: [String] = []
        for url in urls {
            do {
                let file = try await fileImporter.importFile(from: url)
                let item = FileListItem(id: UUID(), audioFile: file, isSelected: true)
                fileList.append(item)
            } catch {
                let msg = "\(url.lastPathComponent): \(error.localizedDescription)"
                errors.append(msg)
            }
        }
        if !errors.isEmpty {
            errorMessage = "一部のファイルを追加できませんでした:\n" + errors.joined(separator: "\n")
        }
    }

    /// ファイルリストの全選択/全解除をトグルする
    /// 全ファイルが未選択の場合は全選択、1つ以上選択されている場合は全解除
    func toggleSelectAll() {
        let hasAnySelected = fileList.contains { $0.isSelected }
        for i in fileList.indices {
            fileList[i].isSelected = !hasAnySelected
        }
    }

    /// ファイルリストから指定された ID のファイルを削除する
    /// - Parameter ids: 削除するファイルの ID セット
    func removeFilesFromList(_ ids: Set<UUID>) {
        fileList.removeAll { ids.contains($0.id) }
    }

    /// ファイルリストの行タップで再生ファイルを切り替える
    func selectFileForPlayback(_ file: AudioFile) {
        audioFile = file
        // 波形データを生成
        waveformData = WaveformDataProvider.loadWaveformData(from: file.url)
        do {
            try audioPlayer.load(audioFile: file)
            stopPlayback()
        } catch {
            ErrorLogger.saveErrorLog(error: error, operation: "プレーヤー読み込み",
                                     context: ["file": file.url.path])
        }
    }

    // MARK: - 複数ファイル一括文字起こし

    /// ファイルリストで選択されたファイルを逐次文字起こしし、結果を結合する
    /// 各ファイルの進捗を個別に追跡し、全体進捗を (i + p) / N で計算する
    /// エラーが発生したファイルはスキップし、残りのファイルの文字起こしを継続する
    /// - Parameter language: 文字起こしに使用する言語
    func transcribeMultipleFiles(language: TranscriptionLanguage) async {
        let selectedFiles = fileList.filter { $0.isSelected }
        guard !selectedFiles.isEmpty else { return }

        // 状態をリセット
        errorMessage = nil
        isTranscribing = true
        transcriptionProgress = 0
        transcript = nil
        summary = nil

        let totalCount = Double(selectedFiles.count)
        var results: [String] = []
        var errors: [String] = []

        for (index, item) in selectedFiles.enumerated() {
            let i = Double(index)

            do {
                let result = try await transcriber.transcribe(
                    audioFile: item.audioFile,
                    language: language,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            // 全体進捗: (i + p) / N
                            self?.transcriptionProgress = (i + progress) / totalCount
                        }
                    }
                )
                results.append(result.text)
            } catch {
                let msg = "\(item.audioFile.fileName): \(error.localizedDescription)"
                errors.append(msg)
            }

            // ファイル完了時の進捗更新
            transcriptionProgress = (i + 1) / totalCount
        }

        // エラーメッセージの記録
        if !errors.isEmpty {
            errorMessage = "一部のファイルで文字起こしに失敗しました:\n" + errors.joined(separator: "\n")
        }

        // 結果テキストをファイル順に結合して transcript にセット
        if !results.isEmpty {
            let combinedText = results.joined(separator: "\n")
            let firstFile = selectedFiles.first!.audioFile
            transcript = Transcript(
                id: UUID(),
                audioFileId: firstFile.id,
                text: combinedText,
                language: language,
                createdAt: Date()
            )
        }

        transcriptionProgress = 1.0
        isTranscribing = false

        // 結合結果を .transcript.txt ファイルとして保存（エクスポート先が設定済みの場合）
        if let exportDir = AWSSettingsViewModel.exportDirectory, let transcript = transcript {
            let baseName = selectedFiles.first?.audioFile.fileName ?? "transcript"
            let transcriptURL = exportDir.appendingPathComponent("\(baseName).transcript.txt")
            do {
                if !FileManager.default.fileExists(atPath: exportDir.path) {
                    try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
                }
                try transcript.text.write(to: transcriptURL, atomically: true, encoding: .utf8)
                lastTranscriptPath = transcriptURL.path
            } catch {
                errorMessage = (errorMessage ?? "") + "\n文字起こしファイルの保存に失敗しました: \(error.localizedDescription)"
            }
        }

        // 要約も自動実行する
        if transcript != nil {
            await startSummarization()

            // 要約結果をファイルに保存
            if let exportDir = AWSSettingsViewModel.exportDirectory, let summary = summary {
                let baseName = selectedFiles.first?.audioFile.fileName ?? "transcript"
                let summaryURL = exportDir.appendingPathComponent("\(baseName).summary.txt")
                do {
                    if !FileManager.default.fileExists(atPath: exportDir.path) {
                        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
                    }
                    try summary.text.write(to: summaryURL, atomically: true, encoding: .utf8)
                    lastSummaryPath = summaryURL.path
                } catch {
                    // 保存失敗は致命的ではない
                }
            }
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
            ErrorLogger.saveErrorLog(error: error, operation: "エクスポート", sourceFileName: audioFile?.fileName)
        } catch {
            errorMessage = error.localizedDescription
            ErrorLogger.saveErrorLog(error: error, operation: "エクスポート", sourceFileName: audioFile?.fileName)
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
        isStartingCapture = true
        // ファイル選択・ファイルリストをクリア
        audioFile = nil
        transcript = nil
        summary = nil
        transcriptionProgress = 0
        fileList.removeAll()
        await stopLevelPreview()
        do {
            try await systemAudioCapture.startCapture(sourceType: selectedAudioSource, splitInterval: TimeInterval(splitIntervalMinutes * 60))
            isCapturingSystemAudio = true
            isStartingCapture = false
        } catch let error as AppError {
            isStartingCapture = false
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録音に失敗しました")
        } catch {
            isStartingCapture = false
            errorMessage = "録音の開始に失敗しました: \(error.localizedDescription)"
        }
    }

    /// システム音声のキャプチャを停止し、録音ファイルを保存する（文字起こしは自動実行しない）
    /// 分割された全ファイルを取得し、最初のファイルを audioFile にセットする
    func stopSystemAudioCapture() async {
        isStoppingCapture = true
        convertingStatus = .saving
        do {
            isCapturingSystemAudio = false
            captureAudioLevel = 0

            let capturedFiles = try await systemAudioCapture.stopCapture()

            // 最初のファイルを audioFile にセット（プレーヤー用）
            if let firstFile = capturedFiles.first {
                audioFile = firstFile
            } else if let firstItem = fileList.first {
                audioFile = firstItem.audioFile
            }
            transcript = nil
            summary = nil
            transcriptionProgress = 0

            // 音声プレーヤーへの読み込み
            if let file = audioFile {
                do {
                    try audioPlayer.load(audioFile: file)
                } catch {
                    ErrorLogger.saveErrorLog(error: error, operation: "録音_プレーヤー読み込み",
                                             context: ["file": file.url.path,
                                                        "ext": file.fileExtension])
                }
                // 波形データを生成
                waveformData = WaveformDataProvider.loadWaveformData(from: file.url)
            }
            stopPlayback()

            // fileList への追加は onFileSplitCompleted で実施済み

            convertingStatus = .completed
            isStoppingCapture = false

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.convertingStatus = .idle }
            }
        } catch let error as AppError {
            convertingStatus = .idle
            isCapturingSystemAudio = false
            captureAudioLevel = 0
            isStoppingCapture = false
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録音に失敗しました")
            ErrorLogger.saveErrorLog(error: error, operation: "録音保存",
                                     context: ["sourceType": "\(selectedAudioSource)"])
        } catch {
            convertingStatus = .idle
            isCapturingSystemAudio = false
            captureAudioLevel = 0
            isStoppingCapture = false
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
        isStartingCapture = true
        // ファイル選択・ファイルリストをクリア
        audioFile = nil
        transcript = nil
        summary = nil
        transcriptionProgress = 0
        fileList.removeAll()
        screenRecorder.saveMode = .videoAndAudio
        do {
            try await screenRecorder.startRecording()
            isRecordingScreen = true
            isStartingCapture = false
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
            isStartingCapture = false
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録画の開始に失敗しました")
        } catch {
            isStartingCapture = false
            errorMessage = "録画の開始に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 画面録画を停止し、RAW 形式で保存する（変換は一時的に無効、文字起こしは自動実行しない）
    func stopScreenRecording() async {
        isStoppingCapture = true
        convertingStatus = .saving
        do {
            isRecordingScreen = false

            let capturedAudio = try await screenRecorder.stopRecording()

            audioFile = capturedAudio
            transcript = nil
            summary = nil
            transcriptionProgress = 0

            // ファイルリストに追加
            fileList.append(FileListItem(id: UUID(), audioFile: capturedAudio, isSelected: true))

            // 音声プレーヤーへの読み込み（MOV の Float32 PCM は再生できない場合がある）
            do {
                try audioPlayer.load(audioFile: capturedAudio)
            } catch {
                ErrorLogger.saveErrorLog(error: error, operation: "録画_プレーヤー読み込み",
                                         context: ["file": capturedAudio.url.path,
                                                    "ext": capturedAudio.fileExtension])
            }
            // 波形データを生成
            waveformData = WaveformDataProvider.loadWaveformData(from: capturedAudio.url)
            stopPlayback()
            convertingStatus = .completed
            isStoppingCapture = false

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.convertingStatus = .idle }
            }
        } catch let error as AppError {
            convertingStatus = .idle
            isRecordingScreen = false
            isStoppingCapture = false
            errorMessage = (error.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "文字起こしに失敗しました", with: "録画の保存に失敗しました")
            ErrorLogger.saveErrorLog(error: error, operation: "録画保存",
                                     context: ["saveMode": "videoAndAudio"])
        } catch {
            convertingStatus = .idle
            isRecordingScreen = false
            isStoppingCapture = false
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
