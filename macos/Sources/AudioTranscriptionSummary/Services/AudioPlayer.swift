// AudioPlayer.swift
// 音声ファイルの再生を担当するサービス
// AVPlayer を使用。readyToPlay を非同期で監視し、準備完了後に再生可能にする

import AVFoundation
import Foundation

final class AudioPlayerService: AudioPlaying {

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    /// readyToPlay になったかどうか
    private(set) var isReady: Bool = false

    var isPlaying: Bool {
        player?.rate != 0 && player?.rate != nil
    }

    var currentTime: TimeInterval {
        guard let player = player else { return 0 }
        let t = CMTimeGetSeconds(player.currentTime())
        return t.isFinite ? t : 0
    }

    var duration: TimeInterval {
        guard let item = playerItem else { return 0 }
        let d = CMTimeGetSeconds(item.duration)
        return d.isFinite && d > 0 ? d : 0
    }

    func load(audioFile: AudioFile) throws {
        player?.pause()
        statusObservation?.invalidate()
        isReady = false

        guard FileManager.default.fileExists(atPath: audioFile.url.path) else {
            throw AppError.corruptedFile
        }

        let asset = AVURLAsset(url: audioFile.url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        if let existing = player {
            existing.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }

        // readyToPlay を非同期で監視（ブロックしない）
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            if observedItem.status == .readyToPlay {
                self?.isReady = true
            }
        }
        // 既に readyToPlay の場合
        if item.status == .readyToPlay {
            isReady = true
        }
    }

    func play() {
        guard isReady else { return }
        // 再生終了位置にいる場合は先頭に戻す
        if let item = playerItem {
            let current = CMTimeGetSeconds(item.currentTime())
            let dur = CMTimeGetSeconds(item.duration)
            if current.isFinite && dur.isFinite && dur > 0 && current >= dur - 0.1 {
                player?.seek(to: .zero)
            }
        }
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func seek(to time: TimeInterval) {
        let d = duration
        let clamped = min(max(time, 0), d > 0 ? d : 0)
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
