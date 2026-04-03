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
    /// 言語自動判別の有効/無効
    @Published var isAutoDetectEnabled: Bool = true
    /// リアルタイム文字起こしの有効/無効
    @Published var isRealtimeEnabled: Bool = true
    /// ストリーミング中かどうか
    @Published var isStreaming: Bool = false
    /// エラーメッセージ
    @Published var errorMessage: String?

    // MARK: - サービス

    private let transcribeClient = RealtimeTranscribeClient()

    /// リアルタイム翻訳用の TranslationViewModel（外部から設定）
    var realtimeTranslationVM: TranslationViewModel?

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
        transcribeClient.onPartialTranscript = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.partialText = text
            }
        }

        transcribeClient.onFinalTranscript = { [weak self] text, lang in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.finalText += text + "\n"
                self.partialText = ""
                if let lang = lang {
                    self.detectedLanguage = lang
                }
                // 確定テキストをリアルタイム翻訳
                await self.realtimeTranslationVM?.translateAppend(text)
            }
        }

        transcribeClient.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = "リアルタイム文字起こしエラー: \(error.localizedDescription)"
            }
        }

        // ストリーミング開始
        let region = AWSSettingsViewModel.currentRegion
        do {
            if isAutoDetectEnabled {
                try await transcribeClient.startStreaming(
                    languageCode: nil,
                    autoDetectLanguages: ["ja-JP", "en-US"],
                    region: region
                )
            } else {
                try await transcribeClient.startStreaming(
                    languageCode: "ja-JP",
                    autoDetectLanguages: nil,
                    region: region
                )
            }
        } catch {
            errorMessage = "ストリーミング開始に失敗しました: \(error.localizedDescription)"
            isStreaming = false
        }
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
}
