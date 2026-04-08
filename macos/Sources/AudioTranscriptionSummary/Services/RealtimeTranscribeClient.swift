// RealtimeTranscribeClient.swift
// Amazon Transcribe Streaming API との接続を管理するクライアント
// 音声ストリームをリアルタイムで送信し、文字起こし結果を受信する

import Foundation
import AWSTranscribeStreaming
import SmithyIdentity

// MARK: - RealtimeTranscribeClient

/// Amazon Transcribe Streaming API を使用したリアルタイム文字起こしクライアント
final class RealtimeTranscribeClient: @unchecked Sendable, RealtimeTranscribing {

    // MARK: - コールバック

    /// 暫定テキスト（PartialTranscript）受信時のコールバック
    var onPartialTranscript: (@Sendable (String) -> Void)?
    /// 確定テキスト（FinalTranscript）受信時のコールバック (text, detectedLanguage)
    var onFinalTranscript: (@Sendable (String, String?) -> Void)?
    /// エラー発生時のコールバック
    var onError: (@Sendable (Error) -> Void)?

    // MARK: - プロパティ

    private var client: TranscribeStreamingClient?
    private var audioStreamContinuation: AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error>.Continuation?
    private var isStreaming = false
    private let lock = NSLock()
    private var reconnectCount = 0
    private let maxReconnectAttempts = 3

    // MARK: - ストリーミング開始

    /// Transcribe Streaming セッションを開始する
    /// - Parameters:
    ///   - languageCode: 言語コード（nil の場合は自動判別）
    ///   - autoDetectLanguages: 自動判別対象の言語コード配列（例: ["ja-JP", "en-US"]）
    ///   - region: AWS リージョン
    func startStreaming(
        languageCode: String? = nil,
        autoDetectLanguages: [String]? = ["ja-JP", "en-US"],
        region: String = "ap-northeast-1"
    ) async throws {
        // AWSClientFactory 経由で認証情報を解決
        let resolver = try AWSClientFactory.makeCredentialResolver()

        let config: TranscribeStreamingClient.TranscribeStreamingClientConfiguration
        if let resolver = resolver {
            config = try await TranscribeStreamingClient.TranscribeStreamingClientConfiguration(
                awsCredentialIdentityResolver: resolver,
                region: region
            )
        } else {
            // SSO プロファイル等: SDK デフォルトの credential resolver を使用
            config = try await TranscribeStreamingClient.TranscribeStreamingClientConfiguration(
                region: region
            )
        }
        client = TranscribeStreamingClient(config: config)

        // 音声ストリームを作成
        let audioStream = AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> { continuation in
            self.lock.lock()
            self.audioStreamContinuation = continuation
            self.isStreaming = true
            self.lock.unlock()
        }

        // StartStreamTranscriptionInput を構築
        var input = StartStreamTranscriptionInput(
            audioStream: audioStream,
            mediaEncoding: .pcm,
            mediaSampleRateHertz: 16000
        )

        // 言語設定: 自動判別 or 手動指定
        if let autoDetect = autoDetectLanguages, languageCode == nil {
            input.identifyLanguage = true
            input.languageOptions = autoDetect.joined(separator: ",")
        } else if let lang = languageCode {
            input.languageCode = TranscribeStreamingClientTypes.LanguageCode(rawValue: lang)
        } else {
            input.languageCode = .jaJp
        }

        isStreaming = true
        reconnectCount = 0

        // ストリーミング開始（バックグラウンドで結果を受信）
        Task { [weak self] in
            do {
                let output = try await self?.client?.startStreamTranscription(input: input)
                guard let resultStream = output?.transcriptResultStream else { return }

                for try await event in resultStream {
                    self?.handleTranscriptEvent(event)
                }
            } catch {
                self?.handleStreamError(error)
            }
        }
    }

    // MARK: - 音声チャンク送信

    /// PCM 音声データチャンクを Transcribe Streaming に送信する
    /// - Parameter data: PCM 16-bit signed LE の音声データ
    func sendAudioChunk(_ data: Data) {
        lock.lock()
        let continuation = audioStreamContinuation
        let streaming = isStreaming
        lock.unlock()

        guard streaming, let continuation = continuation else { return }

        let audioEvent = TranscribeStreamingClientTypes.AudioStream.audioevent(
            .init(audioChunk: data)
        )
        continuation.yield(audioEvent)
    }

    // MARK: - ストリーミング停止

    /// Transcribe Streaming セッションを正常に終了する
    func stopStreaming() {
        lock.lock()
        let continuation = audioStreamContinuation
        isStreaming = false
        audioStreamContinuation = nil
        lock.unlock()

        continuation?.finish()
        client = nil
    }

    // MARK: - イベント処理

    /// Transcribe Streaming からのイベントを処理する
    private func handleTranscriptEvent(_ event: TranscribeStreamingClientTypes.TranscriptResultStream) {
        guard case .transcriptevent(let transcriptEvent) = event else { return }
        guard let results = transcriptEvent.transcript?.results else { return }

        for result in results {
            guard let alternatives = result.alternatives, let best = alternatives.first else { continue }
            let text = best.transcript ?? ""
            let detectedLang = result.languageCode?.rawValue

            if result.isPartial == true {
                // 暫定テキスト
                onPartialTranscript?(text)
            } else {
                // 確定テキスト
                onFinalTranscript?(text, detectedLang)
            }
        }
    }

    /// ストリームエラーを処理する（自動再接続を試みる）
    private func handleStreamError(_ error: Error) {
        lock.lock()
        reconnectCount += 1
        let count = reconnectCount
        lock.unlock()

        if count <= maxReconnectAttempts {
            // 再接続は呼び出し元（ViewModel）に委譲
            onError?(error)
        } else {
            onError?(error)
        }
    }
}
