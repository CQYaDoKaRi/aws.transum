// RealtimeTranscriptionViewModel.swift
// リアルタイム文字起こし・翻訳の状態管理を担当する ViewModel
// TranscribeStreamingClient と TranslateService を連携させる

import Foundation
import AVFoundation
import Combine

// MARK: - RealtimeTranscriptionViewModel

@MainActor
class RealtimeTranscriptionViewModel: ObservableObject {

    // MARK: - Published プロパティ

    /// 確定済みテキスト（FinalTranscript の累積）
    @Published var finalText: String = ""
    /// 暫定テキスト（現在の PartialTranscript）
    @Published var partialText: String = ""
    /// 判別された言語
    @Published var detectedLanguage: String?
    /// 翻訳先言語
    @Published var selectedTargetLanguage: TranslationLanguage = .japanese
    /// 文字起こし言語（auto = 自動検出、それ以外 = 指定言語）
    @Published var selectedLanguage: TranscriptionLanguage = .auto
    /// リアルタイム文字起こしの有効/無効
    @Published var isRealtimeEnabled: Bool = true
    /// ストリーミング中かどうか
    @Published var isStreaming: Bool = false
    /// エラーメッセージ
    @Published var errorMessage: String?

    // MARK: - 自動検出時の言語候補

    /// 自動検出モードで使用する言語候補（Transcribe Streaming は最大5言語）
    static let autoDetectLanguageOptions = ["ja-JP", "en-US", "zh-CN", "ko-KR", "fr-FR"]

    // MARK: - サービス

    /// リアルタイム文字起こしクライアント（DI 対応: プロトコル型）
    private let transcribeClient: RealtimeTranscribing

    /// リアルタイム翻訳用の TranslationViewModel（外部から設定）
    var realtimeTranslationVM: TranslationViewModel?

    /// 表示テキストの最大行数
    private let maxDisplayLines = 500

    /// リアルタイム文字起こしのストリーム出力先ファイルパス
    var streamOutputPath: URL?

    // MARK: - イニシャライザ

    /// デフォルトイニシャライザ（本番用: RealtimeTranscribeClient を使用）
    init() {
        self.transcribeClient = RealtimeTranscribeClient()
    }

    /// DI 用イニシャライザ（テスト時にモックを注入可能）
    init(transcribeClient: RealtimeTranscribing) {
        self.transcribeClient = transcribeClient
    }

    /// テキストを最大行数に制限する（超過分は先頭から削除）
    private func trimToMaxLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxDisplayLines {
            return lines.suffix(maxDisplayLines).joined(separator: "\n")
        }
        return text
    }

    // MARK: - コールバック設定

    /// transcribeClient のコールバックを設定する
    private func setupCallbacks() {
        transcribeClient.onPartialTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.partialText = text
            }
        }

        transcribeClient.onFinalTranscript = { [weak self] text, lang in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.finalText += text + "\n"
                self.finalText = self.trimToMaxLines(self.finalText)
                self.partialText = ""
                if let lang = lang {
                    self.detectedLanguage = lang
                }
                // ストリーム出力: 確定テキストをファイルに逐次追記
                self.appendToStreamFile(text + "\n")
                // 確定テキストをリアルタイム翻訳（文字起こし言語と翻訳先言語が異なる場合のみ）
                if let vm = self.realtimeTranslationVM {
                    let targetLang = vm.selectedTargetLanguage.rawValue
                    // 文字起こし言語を判定（指定言語 or 検出言語）
                    let transcribeLangPrefix: String
                    if self.selectedLanguage != .auto {
                        // 指定言語モード: selectedLanguage のプレフィックス（例: "ja-JP" → "ja"）
                        transcribeLangPrefix = String(self.selectedLanguage.rawValue.prefix(2)).lowercased()
                    } else {
                        // 自動検出モード: 検出された言語のプレフィックス
                        transcribeLangPrefix = self.detectedLanguage?.prefix(2).lowercased() ?? ""
                    }
                    if !transcribeLangPrefix.isEmpty && transcribeLangPrefix != targetLang {
                        await vm.translateAppend(text)
                    }
                }
            }
        }

        transcribeClient.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = "リアルタイム文字起こしエラー: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - ストリーミング開始

    /// リアルタイム文字起こしストリーミングを開始する
    func startStreaming() async {
        guard isRealtimeEnabled else { return }

        // AWS 認証情報の確認
        guard AWSSettingsViewModel.hasValidCredentials else {
            errorMessage = "AWS 認証情報が設定されていません。設定画面から認証情報を入力してください"
            return
        }

        // 状態をリセット
        finalText = ""
        partialText = ""
        detectedLanguage = nil
        errorMessage = nil
        isStreaming = true

        // コールバック設定
        setupCallbacks()

        // 内部ストリーミング開始
        await startStreamingInternal()
    }

    // MARK: - 内部ストリーミング開始

    /// selectedLanguage に基づいてストリーミングを開始する（再接続時にも使用）
    private func startStreamingInternal() async {
        let region = AWSSettingsViewModel.currentRegion
        do {
            if selectedLanguage == .auto {
                // 自動検出: 主要言語を languageOptions に渡す
                try await transcribeClient.startStreaming(
                    languageCode: nil,
                    autoDetectLanguages: Self.autoDetectLanguageOptions,
                    region: region
                )
            } else {
                // 指定言語: 選択された言語コードを使用
                try await transcribeClient.startStreaming(
                    languageCode: selectedLanguage.rawValue,
                    autoDetectLanguages: nil,
                    region: region
                )
            }
        } catch {
            errorMessage = "ストリーミング開始に失敗しました: \(error.localizedDescription)"
            isStreaming = false
        }
    }

    // MARK: - ストリーミング中の言語切り替え

    /// 言語設定変更時にストリーミングを再接続する
    /// - 確定テキスト（finalText）は保持
    /// - 暫定テキスト（partialText）はクリア
    func restartStreamingWithNewLanguage() async {
        guard isStreaming else { return }

        // 現在のストリーミングを停止
        transcribeClient.stopStreaming()
        // 暫定テキストをクリア（確定テキストは保持）
        partialText = ""
        errorMessage = nil

        // コールバックを再設定
        setupCallbacks()

        // 新しい言語設定でストリーミング再開
        await startStreamingInternal()
    }

    // MARK: - ストリーミング停止

    /// リアルタイム文字起こしストリーミングを停止する
    func stopStreaming() {
        transcribeClient.stopStreaming()
        isStreaming = false
    }

    // MARK: - 音声バッファ送信

    /// CMSampleBuffer を PCM に変換して Transcribe Streaming に送信する
    nonisolated func sendAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        if let pcmData = AudioBufferConverter.convertToPCM16(sampleBuffer: sampleBuffer) {
            transcribeClient.sendAudioChunk(pcmData)
        }
    }

    // MARK: - Transcript モデルへの変換

    /// リアルタイム文字起こしの最終結果を Transcript モデルに変換する
    func toTranscript(audioFileId: UUID) -> Transcript? {
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let lang: TranscriptionLanguage
        if let detected = detectedLanguage, detected.hasPrefix("en") {
            lang = .english
        } else {
            lang = .japanese
        }

        return Transcript(
            id: UUID(),
            audioFileId: audioFileId,
            text: text,
            language: lang,
            createdAt: Date()
        )
    }

    // MARK: - ストリーム出力

    /// 確定テキストをストリーム出力ファイルに逐次追記する
    private func appendToStreamFile(_ text: String) {
        guard let path = streamOutputPath else { return }
        do {
            if FileManager.default.fileExists(atPath: path.path) {
                let handle = try FileHandle(forWritingTo: path)
                handle.seekToEndOfFile()
                if let data = text.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try text.write(to: path, atomically: false, encoding: .utf8)
            }
        } catch {
            // ストリーム出力の失敗は録音に影響させない
        }
    }
}
