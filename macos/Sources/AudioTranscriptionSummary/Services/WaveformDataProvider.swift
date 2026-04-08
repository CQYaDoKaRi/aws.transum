// WaveformDataProvider.swift
// 音声ファイルから波形描画用のサンプルデータを抽出するプロバイダー
// AVAudioFile でサンプルを読み込み、ダウンサンプリングして正規化した配列を返す

import AVFoundation

/// 波形描画用のサンプルデータを提供する
struct WaveformDataProvider {

    /// 音声ファイルから波形データを抽出する
    /// - Parameters:
    ///   - url: 音声ファイルの URL
    ///   - sampleCount: 出力するサンプル数（描画解像度、デフォルト: 200）
    /// - Returns: 正規化された振幅値の配列（0.0〜1.0）。エラー時は空配列を返す
    static func loadWaveformData(from url: URL, sampleCount: Int = 200) -> [Float] {
        guard sampleCount > 0 else { return [] }

        // AVAudioFile でファイルを開く
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            return []
        }

        let totalFrames = AVAudioFrameCount(audioFile.length)
        guard totalFrames > 0 else { return [] }

        // PCM バッファにサンプルを読み込む
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: audioFile.processingFormat.sampleRate,
                                         channels: audioFile.processingFormat.channelCount,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return []
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return []
        }

        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        // 全サンプルを sampleCount 個のビンに分割し、各ビンの最大振幅を取得
        let samplesPerBin = max(frameCount / sampleCount, 1)
        var amplitudes = [Float](repeating: 0, count: sampleCount)

        for bin in 0..<sampleCount {
            let start = bin * frameCount / sampleCount
            let end = min((bin + 1) * frameCount / sampleCount, frameCount)
            guard start < end else { continue }

            var maxAmplitude: Float = 0
            for i in start..<end {
                // 全チャンネルの最大振幅を取得
                for ch in 0..<Int(format.channelCount) {
                    let sample = abs(channelData[ch][i])
                    if sample > maxAmplitude {
                        maxAmplitude = sample
                    }
                }
            }
            amplitudes[bin] = maxAmplitude
        }

        // 全体の最大値で正規化（0.0〜1.0）
        let globalMax = amplitudes.max() ?? 0
        guard globalMax > 0 else { return amplitudes }

        for i in 0..<amplitudes.count {
            amplitudes[i] /= globalMax
        }

        return amplitudes
    }
}
