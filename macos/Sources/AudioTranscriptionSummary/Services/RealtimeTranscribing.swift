// RealtimeTranscribing.swift
// RealtimeTranscribeClient のテスト用プロトコル定義
// テスト時にモックを注入するための抽象化レイヤー

import Foundation

// MARK: - RealtimeTranscribing プロトコル

/// リアルタイム文字起こしクライアントのプロトコル
/// テスト時に `MockRealtimeTranscribeClient` を注入可能にする
protocol RealtimeTranscribing: AnyObject, Sendable {

    // MARK: - コールバック

    /// 暫定テキスト（PartialTranscript）受信時のコールバック
    var onPartialTranscript: (@Sendable (String) -> Void)? { get set }
    /// 確定テキスト（FinalTranscript）受信時のコールバック (text, detectedLanguage)
    var onFinalTranscript: (@Sendable (String, String?) -> Void)? { get set }
    /// エラー発生時のコールバック
    var onError: (@Sendable (Error) -> Void)? { get set }

    // MARK: - メソッド

    /// Transcribe Streaming セッションを開始する
    /// - Parameters:
    ///   - languageCode: 言語コード（nil の場合は自動判別）
    ///   - autoDetectLanguages: 自動判別対象の言語コード配列
    ///   - region: AWS リージョン
    func startStreaming(
        languageCode: String?,
        autoDetectLanguages: [String]?,
        region: String
    ) async throws

    /// PCM 音声データチャンクを送信する
    /// - Parameter data: PCM 16-bit signed LE の音声データ
    func sendAudioChunk(_ data: Data)

    /// ストリーミングセッションを停止する
    func stopStreaming()
}
