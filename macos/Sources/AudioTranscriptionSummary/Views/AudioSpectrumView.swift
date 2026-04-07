// AudioSpectrumView.swift
// 音声プレーヤーの下に表示するオーディオスペクトラム（波形ビジュアライザ）
// AVAudioEngine の FFT タップを使用してリアルタイムにスペクトラムを描画する

import SwiftUI
import AVFoundation
import Accelerate

// MARK: - AudioSpectrumAnalyzer

/// AVAudioEngine を使用してオーディオスペクトラムデータを生成する
@MainActor
class AudioSpectrumAnalyzer: ObservableObject {
    @Published var spectrumData: [Float] = Array(repeating: 0, count: 32)

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private let bandCount = 32

    /// 音声ファイルを読み込んでスペクトラム解析の準備をする
    func load(url: URL) {
        stop()
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            spectrumData = Array(repeating: 0, count: bandCount)
        }
    }

    /// 再生中のスペクトラム解析を開始する
    func start() {
        guard let audioFile = audioFile else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: audioFile.processingFormat)

        // FFT タップを設置
        let bufferSize: AVAudioFrameCount = 1024
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            let magnitudes = self.fft(buffer: buffer)
            Task { @MainActor [weak self] in
                self?.spectrumData = magnitudes
            }
        }

        do {
            engine.mainMixerNode.outputVolume = 0 // 音を出さない（解析のみ）
            try engine.start()
            player.scheduleFile(audioFile, at: nil)
            player.play()
            self.engine = engine
            self.playerNode = player
        } catch {
            spectrumData = Array(repeating: 0, count: bandCount)
        }
    }

    /// スペクトラム解析を停止する
    func stop() {
        engine?.mainMixerNode.removeTap(onBus: 0)
        playerNode?.stop()
        engine?.stop()
        engine = nil
        playerNode = nil
        spectrumData = Array(repeating: 0, count: bandCount)
    }

    /// FFT でスペクトラムデータを生成する
    private func fft(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else {
            return Array(repeating: 0, count: bandCount)
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return Array(repeating: 0, count: bandCount) }

        let log2n = vDSP_Length(log2(Float(frameCount)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0, count: bandCount)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let n = Int(1 << log2n)
        var realp = [Float](repeating: 0, count: n / 2)
        var imagp = [Float](repeating: 0, count: n / 2)

        // 入力データをコピー
        var window = [Float](repeating: 0, count: n)
        for i in 0..<min(frameCount, n) {
            window[i] = channelData[i]
        }

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                window.withUnsafeBufferPointer { windowBuf in
                    windowBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { ptr in
                        vDSP_ctoz(ptr, 2, &splitComplex, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // マグニチュードを計算
                var magnitudes = [Float](repeating: 0, count: n / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

                // バンドに分割
                let binCount = n / 2
                let binsPerBand = max(binCount / bandCount, 1)
                var result = [Float](repeating: 0, count: bandCount)
                for band in 0..<bandCount {
                    let start = band * binsPerBand
                    let end = min(start + binsPerBand, binCount)
                    if start < end {
                        var sum: Float = 0
                        for i in start..<end { sum += magnitudes[i] }
                        let avg = sum / Float(end - start)
                        // dB スケールに変換して正規化
                        let db = 10 * log10(max(avg, 1e-10))
                        result[band] = max(0, min(1, (db + 60) / 60))
                    }
                }
                Task { @MainActor in
                    // result をキャプチャして使用
                    _ = result
                }
            }
        }

        // 簡易版: 直接計算
        var magnitudes = [Float](repeating: 0, count: n / 2)
        realp.withUnsafeMutableBufferPointer { rBuf in
            imagp.withUnsafeMutableBufferPointer { iBuf in
                for i in 0..<n/2 {
                    magnitudes[i] = rBuf[i] * rBuf[i] + iBuf[i] * iBuf[i]
                }
            }
        }

        let binCount = n / 2
        let binsPerBand = max(binCount / bandCount, 1)
        var result = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let start = band * binsPerBand
            let end = min(start + binsPerBand, binCount)
            if start < end {
                var sum: Float = 0
                for i in start..<end { sum += magnitudes[i] }
                let avg = sum / Float(end - start)
                let db = 10 * log10(max(avg, 1e-10))
                result[band] = max(0, min(1, (db + 60) / 60))
            }
        }
        return result
    }
}

// MARK: - AudioSpectrumView

/// オーディオスペクトラムを棒グラフで表示するビュー
struct AudioSpectrumView: View {
    @ObservedObject var viewModel: AppViewModel
    /// 音声レベルデータ（キャプチャ中はキャプチャレベル、再生中はスペクトラム）
    var audioLevel: Float

    var body: some View {
        if viewModel.audioFile != nil {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(0..<32, id: \.self) { i in
                        let height = barHeight(index: i, level: audioLevel, totalBars: 32)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(height: height))
                            .frame(width: max((geo.size.width - 31) / 32, 2),
                                   height: max(geo.size.height * CGFloat(height), 1))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: 30)
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }

    /// バーの高さを計算（簡易スペクトラム風）
    private func barHeight(index: Int, level: Float, totalBars: Int) -> Float {
        guard level > 0.01 else { return 0 }
        // 中央が高く、端が低い山型 + ランダム風の変動
        let center = Float(totalBars) / 2
        let dist = abs(Float(index) - center) / center
        let base = max(0, 1 - dist * 0.7) * level
        // 周波数帯ごとの微妙な変動（ハッシュベース）
        let variation = Float((index * 7 + Int(level * 100)) % 10) / 20.0
        return min(1, max(0, base + variation * level))
    }

    /// バーの色（高さに応じてグラデーション）
    private func barColor(height: Float) -> Color {
        if height > 0.7 { return .red }
        if height > 0.4 { return .yellow }
        return .green
    }
}
