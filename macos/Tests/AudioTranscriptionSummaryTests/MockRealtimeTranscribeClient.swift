// MockRealtimeTranscribeClient.swift
// RealtimeTranscribing プロトコルのテスト用モック
// startStreaming / stopStreaming の呼び出し回数・パラメータを記録し、
// shouldThrowOnStart フラグでエラーシミュレーションを可能にする

import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockRealtimeTranscribeClient

/// テスト用のリアルタイム文字起こしクライアントモック
final class MockRealtimeTranscribeClient: RealtimeTranscribing, @unchecked Sendable {

    // MARK: - コールバック

    /// 暫定テキスト受信時のコールバック
    var onPartialTranscript: (@Sendable (String) -> Void)?
    /// 確定テキスト受信時のコールバック
    var onFinalTranscript: (@Sendable (String, String?) -> Void)?
    /// エラー発生時のコールバック
    var onError: (@Sendable (Error) -> Void)?

    // MARK: - 記録用プロパティ

    /// startStreaming の呼び出し回数
    var startStreamingCallCount = 0
    /// 最後に受信した languageCode パラメータ
    var lastLanguageCode: String?
    /// 最後に受信した autoDetectLanguages パラメータ
    var lastAutoDetectLanguages: [String]?
    /// 最後に受信した region パラメータ
    var lastRegion: String?
    /// stopStreaming の呼び出し回数
    var stopStreamingCallCount = 0
    /// sendAudioChunk の呼び出し回数
    var sendAudioChunkCallCount = 0

    // MARK: - エラーシミュレーション

    /// true の場合、startStreaming でエラーをスローする
    var shouldThrowOnStart = false

    /// startStreaming でスローするエラー
    enum MockError: Error, LocalizedError {
        case simulatedStartFailure

        var errorDescription: String? {
            "モックエラー: ストリーミング開始に失敗しました"
        }
    }

    // MARK: - RealtimeTranscribing 準拠

    func startStreaming(
        languageCode: String?,
        autoDetectLanguages: [String]?,
        region: String
    ) async throws {
        startStreamingCallCount += 1
        lastLanguageCode = languageCode
        lastAutoDetectLanguages = autoDetectLanguages
        lastRegion = region

        if shouldThrowOnStart {
            throw MockError.simulatedStartFailure
        }
    }

    func sendAudioChunk(_ data: Data) {
        sendAudioChunkCallCount += 1
    }

    func stopStreaming() {
        stopStreamingCallCount += 1
    }
}
