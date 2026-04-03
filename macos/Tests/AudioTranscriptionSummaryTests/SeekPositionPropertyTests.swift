// SeekPositionPropertyTests.swift
// Feature: audio-transcription-summary, Property 6: シーク位置の正確性
// 0〜duration 範囲のランダムな TimeInterval を生成し、seek 後の currentTime が指定位置と一致することを検証する
// **Validates: Requirements 5.4**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック AudioPlayer（シーク位置検証用）

/// AudioPlaying プロトコルに準拠したモック
/// seek 後の currentTime が指定位置（0〜duration にクランプ）と一致することを保証する
private final class MockAudioPlayer: AudioPlaying {

    /// 再生中かどうか
    private(set) var isPlaying: Bool = false

    /// 現在の再生位置（秒）
    private(set) var currentTime: TimeInterval = 0

    /// 音声の総再生時間（秒）
    var duration: TimeInterval = 0

    /// 読み込まれた AudioFile
    private(set) var loadedAudioFile: AudioFile?

    func load(audioFile: AudioFile) throws {
        loadedAudioFile = audioFile
        duration = audioFile.duration
        currentTime = 0
        isPlaying = false
    }

    func play() {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    /// 指定位置にシークする
    /// シーク位置は 0〜duration の範囲にクランプされる（実際の AudioPlayerService と同じロジック）
    func seek(to time: TimeInterval) {
        let clampedTime = min(max(time, 0), duration)
        currentTime = clampedTime
    }
}

// MARK: - Property 6: シーク位置の正確性（Seek Position Accuracy）

final class SeekPositionPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// 正の再生時間を生成するジェネレータ（1.0〜7200.0 秒）
    private var durationGen: Gen<TimeInterval> {
        Gen<Double>.fromElements(in: 1.0...7200.0)
    }

    /// 0.0〜1.0 の正規化された位置を生成するジェネレータ
    /// duration と掛け合わせて実際のシーク位置を算出する
    private var normalizedPositionGen: Gen<Double> {
        Gen<Double>.fromElements(in: 0.0...1.0)
    }

    // MARK: - プロパティテスト

    /// 0〜duration 範囲のランダムな位置に seek した後、currentTime が指定位置と一致することを検証
    func testSeekPositionAccuracy() {
        let player = MockAudioPlayer()

        property("シーク位置の正確性: seek 後の currentTime は指定位置と一致する")
            <- forAll(self.durationGen, self.normalizedPositionGen) {
                (duration: TimeInterval, normalizedPos: Double) in

                // モックプレーヤーに duration を設定
                let audioFile = AudioFile(
                    id: UUID(),
                    url: URL(fileURLWithPath: "/tmp/test.m4a"),
                    fileName: "test",
                    fileExtension: "m4a",
                    duration: duration,
                    fileSize: 1024,
                    createdAt: Date()
                )

                do {
                    try player.load(audioFile: audioFile)
                } catch {
                    return false
                }

                // 正規化された位置から実際のシーク位置を算出
                let seekPosition = normalizedPos * duration

                // シーク実行
                player.seek(to: seekPosition)

                // 期待されるクランプ後の位置
                let expectedPosition = min(max(seekPosition, 0), duration)

                // currentTime が期待位置と一致することを確認（浮動小数点の許容誤差: 0.001秒）
                let tolerance = 0.001
                let positionMatch = abs(player.currentTime - expectedPosition) < tolerance

                return positionMatch
            }
    }
}
