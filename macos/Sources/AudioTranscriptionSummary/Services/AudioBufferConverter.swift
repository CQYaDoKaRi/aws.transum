// AudioBufferConverter.swift
// CMSampleBuffer を Amazon Transcribe Streaming が要求する
// PCM 16-bit signed little-endian 形式に変換するユーティリティ

import AVFoundation
import Foundation

enum AudioBufferConverter {

    /// CMSampleBuffer → PCM 16-bit signed little-endian Data に変換する
    /// ScreenCaptureKit は Float32、マイクは Int16 で出力するため両方に対応
    /// - Parameters:
    ///   - sampleBuffer: 変換元の CMSampleBuffer
    ///   - targetSampleRate: 出力サンプルレート（デフォルト: 16000Hz）
    /// - Returns: PCM 16-bit LE の Data、変換失敗時は nil
    static func convertToPCM16(sampleBuffer: CMSampleBuffer, targetSampleRate: Double = 16000) -> Data? {
        guard let dataBuffer = sampleBuffer.dataBuffer else { return nil }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &length, dataPointerOut: &dataPointer
        )
        guard status == noErr, let pointer = dataPointer, length > 0 else { return nil }

        // フォーマット情報を取得
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        let sourceSampleRate = asbd.pointee.mSampleRate
        let sourceChannels = Int(asbd.pointee.mChannelsPerFrame)
        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        // ソースデータを Int16 サンプル配列に変換
        var int16Samples: [Int16]

        if isFloat {
            // Float32 → Int16 変換（ScreenCaptureKit の出力形式）
            let floatCount = length / MemoryLayout<Float32>.size
            guard floatCount > 0 else { return nil }
            int16Samples = [Int16](repeating: 0, count: floatCount)
            pointer.withMemoryRebound(to: Float32.self, capacity: floatCount) { floats in
                for i in 0..<floatCount {
                    let clamped = max(-1.0, min(1.0, floats[i]))
                    int16Samples[i] = Int16(clamped * Float32(Int16.max))
                }
            }
        } else {
            // 既に Int16（マイクの出力形式）
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return nil }
            int16Samples = [Int16](repeating: 0, count: sampleCount)
            pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
                for i in 0..<sampleCount { int16Samples[i] = samples[i] }
            }
        }

        // ステレオ → モノラル変換（Transcribe Streaming はモノラルを推奨）
        if sourceChannels >= 2 {
            let monoCount = int16Samples.count / sourceChannels
            var monoSamples = [Int16](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                var sum: Int32 = 0
                for ch in 0..<sourceChannels {
                    sum += Int32(int16Samples[i * sourceChannels + ch])
                }
                monoSamples[i] = Int16(sum / Int32(sourceChannels))
            }
            int16Samples = monoSamples
        }

        // リサンプリング（簡易線形補間）
        if sourceSampleRate != targetSampleRate && sourceSampleRate > 0 {
            let ratio = targetSampleRate / (sourceSampleRate / Double(max(sourceChannels, 1)) * Double(max(sourceChannels, 1)))
            // ステレオ→モノラル変換後のサンプルレートで計算
            let actualSourceRate = sourceSampleRate
            let actualRatio = targetSampleRate / actualSourceRate
            let outputCount = Int(Double(int16Samples.count) * actualRatio)
            guard outputCount > 0 else { return nil }
            var resampled = [Int16](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                let srcIndex = Double(i) / actualRatio
                let idx = Int(srcIndex)
                let frac = Float(srcIndex - Double(idx))
                if idx + 1 < int16Samples.count {
                    let a = Float(int16Samples[idx])
                    let b = Float(int16Samples[idx + 1])
                    resampled[i] = Int16(a + (b - a) * frac)
                } else if idx < int16Samples.count {
                    resampled[i] = int16Samples[idx]
                }
            }
            int16Samples = resampled
        }

        // Int16 配列 → Data に変換（little-endian）
        return int16Samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}
