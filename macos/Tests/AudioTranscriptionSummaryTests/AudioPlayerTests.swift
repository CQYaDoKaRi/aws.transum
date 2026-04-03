// AudioPlayerTests.swift
// AudioPlayer サービスのユニットテスト
// AudioPlaying プロトコルに準拠したモックを使用して、再生制御機能を検証する
// 要件: 5.1, 5.3

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockAudioPlayer（テスト用モック）

/// AudioPlaying プロトコルに準拠したモック実装
/// 再生/一時停止の状態遷移をシミュレートする
private final class MockAudioPlayer: AudioPlaying {

    /// 再生中かどうか
    private(set) var isPlaying: Bool = false

    /// 現在の再生位置（秒）
    private(set) var currentTime: TimeInterval = 0

    /// 音声の総再生時間（秒）
    var duration: TimeInterval = 0

    /// play が呼ばれた回数
    private(set) var playCallCount = 0

    /// pause が呼ばれた回数
    private(set) var pauseCallCount = 0

    /// seek が呼ばれた回数
    private(set) var seekCallCount = 0

    /// load が呼ばれた回数
    private(set) var loadCallCount = 0

    func load(audioFile: AudioFile) throws {
        loadCallCount += 1
        duration = audioFile.duration
        currentTime = 0
        isPlaying = false
    }

    func play() {
        playCallCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }

    func seek(to time: TimeInterval) {
        seekCallCount += 1
        let clampedTime = min(max(time, 0), duration)
        currentTime = clampedTime
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の AudioFile を生成するヘルパー関数
private func makeTestAudioFile(
    fileName: String = "test_audio",
    duration: TimeInterval = 120.0
) -> AudioFile {
    AudioFile(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/\(fileName).m4a"),
        fileName: fileName,
        fileExtension: "m4a",
        duration: duration,
        fileSize: 1024000,
        createdAt: Date()
    )
}

// MARK: - 再生/一時停止の状態遷移テスト（要件 5.1, 5.3）

@Suite("AudioPlayer 再生/一時停止の状態遷移テスト")
struct AudioPlayerPlaybackStateTests {

    /// 初期状態で isPlaying が false であることを確認
    @Test func initialStateIsNotPlaying() {
        let player = MockAudioPlayer()
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 0)
    }

    /// load 後に duration が設定され、isPlaying が false のままであることを確認
    @Test func loadSetsUpPlayer() throws {
        let player = MockAudioPlayer()
        let audioFile = makeTestAudioFile(duration: 180.0)

        try player.load(audioFile: audioFile)

        #expect(player.duration == 180.0)
        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.loadCallCount == 1)
    }

    /// play() で isPlaying が true になることを確認（要件 5.1）
    @Test func playStartsPlayback() throws {
        let player = MockAudioPlayer()
        let audioFile = makeTestAudioFile()

        try player.load(audioFile: audioFile)
        player.play()

        #expect(player.isPlaying == true)
        #expect(player.playCallCount == 1)
    }

    /// pause() で isPlaying が false になることを確認（要件 5.3）
    @Test func pauseStopsPlayback() throws {
        let player = MockAudioPlayer()
        let audioFile = makeTestAudioFile()

        try player.load(audioFile: audioFile)
        player.play()
        #expect(player.isPlaying == true)

        player.pause()
        #expect(player.isPlaying == false)
        #expect(player.pauseCallCount == 1)
    }

    /// play → pause → play の状態遷移が正しく動作することを確認
    @Test func playPausePlayTransition() throws {
        let player = MockAudioPlayer()
        let audioFile = makeTestAudioFile()

        try player.load(audioFile: audioFile)

        // 再生開始
        player.play()
        #expect(player.isPlaying == true)

        // 一時停止
        player.pause()
        #expect(player.isPlaying == false)

        // 再度再生
        player.play()
        #expect(player.isPlaying == true)

        #expect(player.playCallCount == 2)
        #expect(player.pauseCallCount == 1)
    }

    /// 複数回 pause を呼んでも安全であることを確認
    @Test func multiplePausesAreSafe() throws {
        let player = MockAudioPlayer()
        let audioFile = makeTestAudioFile()

        try player.load(audioFile: audioFile)
        player.play()

        player.pause()
        player.pause()
        player.pause()

        #expect(player.isPlaying == false)
        #expect(player.pauseCallCount == 3)
    }

    /// load を再度呼ぶと状態がリセットされることを確認
    @Test func reloadResetsState() throws {
        let player = MockAudioPlayer()
        let audioFile1 = makeTestAudioFile(fileName: "audio1", duration: 60.0)
        let audioFile2 = makeTestAudioFile(fileName: "audio2", duration: 300.0)

        try player.load(audioFile: audioFile1)
        player.play()
        player.seek(to: 30.0)
        #expect(player.isPlaying == true)
        #expect(player.currentTime == 30.0)

        // 新しいファイルを読み込み
        try player.load(audioFile: audioFile2)

        #expect(player.isPlaying == false)
        #expect(player.currentTime == 0)
        #expect(player.duration == 300.0)
        #expect(player.loadCallCount == 2)
    }
}
