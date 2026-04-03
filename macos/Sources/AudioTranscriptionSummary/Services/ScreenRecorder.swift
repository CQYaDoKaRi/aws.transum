// ScreenRecorder.swift
// 画面録画サービス。映像+音声を MOV にパススルー保存し、
// 停止後に MP4 に変換。音声も別途 AVAssetReader + AVAssetWriter で MP3 に変換して保存する。

import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreImage

@MainActor
protocol ScreenRecorderDelegate: AnyObject {
    func recorderDidStart()
    func recorderDidStop()
    func recorderDidFail(with error: Error)
    func recorderDidUpdateLevel(_ level: Float)
}

/// 画面録画の保存モード
enum ScreenRecordingSaveMode: String, CaseIterable {
    case videoAndAudio = "動画＋音声"
    case audioOnly = "音声のみ"
}

final class ScreenRecorder: NSObject, @unchecked Sendable {

    private var stream: SCStream?

    // 動画用（パススルー MOV）
    private var videoWriter: AVAssetWriter?
    private var videoVideoInput: AVAssetWriterInput?
    private var videoAudioInput: AVAssetWriterInput?
    private var videoAudioInitialized = false
    private var videoSessionStarted = false

    // 音声専用（パススルー MOV）
    private var audioWriter: AVAssetWriter?
    private var audioOnlyInput: AVAssetWriterInput?
    private var audioOnlyInitialized = false
    private var audioSessionStarted = false

    private(set) var isRecording = false
    private var rawVideoURL: URL?
    private var rawAudioURL: URL?
    private var finalVideoURL: URL?
    private var finalAudioURL: URL?
    weak var delegate: (any ScreenRecorderDelegate)?
    private var recordingStartTime: Date?
    private let lock = NSLock()
    /// 保存モード
    var saveMode: ScreenRecordingSaveMode = .videoAndAudio
    /// 最新のプレビューフレーム（CGImage）
    private(set) var latestPreviewFrame: CGImage?

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    // MARK: - 録画開始

    func startRecording() async throws {
        guard !isRecording else { return }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -10,
                                    userInfo: [NSLocalizedDescriptionKey: "画面収録の権限が必要です。「システム設定 > プライバシーとセキュリティ > 画面収録とシステム音声」でこのアプリ（またはターミナル）を許可してください。"]))
        }
        guard let display = content.displays.first else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "ディスプレイが見つかりません"]))
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width; config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = true; config.sampleRate = 48000; config.channelCount = 2
        config.excludesCurrentProcessAudio = false

        let saveDir = AWSSettingsViewModel.recordingDirectory
        if !FileManager.default.fileExists(atPath: saveDir.path) {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        }
        let d = Self.fmt.string(from: Date())

        // RAW は一時ディレクトリに保存
        let uid = UUID().uuidString
        let rvURL = FileManager.default.temporaryDirectory.appendingPathComponent("_raw_video_\(d)_\(uid).mov")
        let raURL = FileManager.default.temporaryDirectory.appendingPathComponent("_raw_audio_\(d)_\(uid).mov")
        rawVideoURL = rvURL; rawAudioURL = raURL
        // 最終ファイルは保存先ディレクトリに配置
        finalVideoURL = saveDir.appendingPathComponent("screen_recording_\(d).mov")
        finalAudioURL = saveDir.appendingPathComponent("screen_audio_\(d).m4a")

        // 動画 Writer（音声のみモードでは作成しない）
        if saveMode == .videoAndAudio {
            let vW = try AVAssetWriter(outputURL: rvURL, fileType: .mov)
            let vSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: display.width, AVVideoHeightKey: display.height
            ]
            let vvI = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            vvI.expectsMediaDataInRealTime = true
            vW.add(vvI); vW.startWriting()
            videoWriter = vW; videoVideoInput = vvI
        } else {
            videoWriter = nil; videoVideoInput = nil
        }
        videoAudioInput = nil; videoAudioInitialized = false; videoSessionStarted = false

        // 音声専用 Writer（遅延パススルー）
        let aW = try AVAssetWriter(outputURL: raURL, fileType: .mov)
        aW.startWriting()
        audioWriter = aW; audioOnlyInput = nil
        audioOnlyInitialized = false; audioSessionStarted = false

        let cs = SCStream(filter: filter, configuration: config, delegate: self)
        if saveMode == .videoAndAudio {
            try cs.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        }
        try cs.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await cs.startCapture()

        stream = cs; isRecording = true; recordingStartTime = Date()
        await MainActor.run { [weak self] in self?.delegate?.recorderDidStart() }
    }

    // MARK: - 録画停止

    func stopRecording() async throws -> AudioFile {
        guard isRecording else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "録画が開始されていません"]))
        }
        if let s = stream { try await s.stopCapture() }

        videoVideoInput?.markAsFinished(); videoAudioInput?.markAsFinished()
        await videoWriter?.finishWriting()
        audioOnlyInput?.markAsFinished()
        await audioWriter?.finishWriting()

        isRecording = false
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        await MainActor.run { [weak self] in self?.delegate?.recorderDidStop() }

        guard let raURL = rawAudioURL else {
            throw AppError.corruptedFile
        }

        // 動画＋音声モードの場合、動画 MOV を保存先にコピー
        if saveMode == .videoAndAudio, let rvURL = rawVideoURL, let fvURL = finalVideoURL {
            if FileManager.default.fileExists(atPath: rvURL.path) {
                try? FileManager.default.moveItem(at: rvURL, to: fvURL)
            }
        } else if let rvURL = rawVideoURL {
            // 音声のみモード: 動画 RAW を削除
            try? FileManager.default.removeItem(at: rvURL)
        }

        // RAW 音声 MOV → M4A に変換
        var audioURL: URL
        var audioExt: String
        if let faURL = finalAudioURL {
            do {
                try await convertAudioToM4A(from: raURL, to: faURL)
                audioURL = faURL
                audioExt = "m4a"
                try? FileManager.default.removeItem(at: raURL)
            } catch {
                // M4A 変換失敗 → RAW を保存先にコピー
                let fallbackURL = faURL.deletingPathExtension().appendingPathExtension("mov")
                try? FileManager.default.moveItem(at: raURL, to: fallbackURL)
                audioURL = fallbackURL
                audioExt = "mov"
            }
        } else {
            audioURL = raURL
            audioExt = "mov"
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        let audioFile = AudioFile(
            id: UUID(), url: audioURL,
            fileName: audioURL.deletingPathExtension().lastPathComponent,
            fileExtension: audioExt, duration: duration,
            fileSize: fileSize, createdAt: Date()
        )
        stream = nil; videoWriter = nil; videoVideoInput = nil; videoAudioInput = nil
        audioWriter = nil; audioOnlyInput = nil
        return audioFile
    }

    // MARK: - キャンセル

    func cancelRecording() async {
        if let s = stream { try? await s.stopCapture() }
        videoVideoInput?.markAsFinished(); videoAudioInput?.markAsFinished()
        await videoWriter?.finishWriting()
        audioOnlyInput?.markAsFinished(); await audioWriter?.finishWriting()
        for url in [rawVideoURL, rawAudioURL, finalVideoURL, finalAudioURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false; cleanup()
        await MainActor.run { [weak self] in self?.delegate?.recorderDidStop() }
    }

    private func cleanup() {
        stream = nil; videoWriter = nil; videoVideoInput = nil; videoAudioInput = nil
        audioWriter = nil; audioOnlyInput = nil
        rawVideoURL = nil; rawAudioURL = nil; finalVideoURL = nil; finalAudioURL = nil
    }

    // MARK: - 変換

    private func convertVideoToMP4(from src: URL, to dst: URL) async throws {
        let asset = AVAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -3,
                                    userInfo: [NSLocalizedDescriptionKey: "動画変換セッションの作成に失敗"]))
        }
        session.outputURL = dst; session.outputFileType = .mp4
        await session.export()
        guard session.status == .completed else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -4,
                                    userInfo: [NSLocalizedDescriptionKey: "動画変換に失敗: \(session.error?.localizedDescription ?? "")"]))
        }
    }

    private func convertAudioToM4A(from src: URL, to dst: URL) async throws {
        let asset = AVAsset(url: src)
        let reader = try AVAssetReader(asset: asset)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "ScreenRecorder", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "音声トラックがありません"])
        }

        var channels: Int = 2
        if let fmts = try? await audioTrack.load(.formatDescriptions),
           let fd = fmts.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd) {
            channels = max(Int(asbd.pointee.mChannelsPerFrame), 1)
        }
        let outCh = min(channels, 2)

        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: outCh,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        guard reader.canAdd(readerOutput) else {
            throw NSError(domain: "ScreenRecorder", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "音声読み出しの追加に失敗"])
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: dst, fileType: .m4a)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: outCh,
            AVEncoderBitRateKey: 128_000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "ScreenRecorder", code: -7,
                          userInfo: [NSLocalizedDescriptionKey: "M4A 書き込みの追加に失敗"])
        }
        writer.add(writerInput)

        reader.startReading(); writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "screen.m4a")) {
                while writerInput.isReadyForMoreMediaData {
                    if let buf = readerOutput.copyNextSampleBuffer() { writerInput.append(buf) }
                    else { writerInput.markAsFinished(); cont.resume(); return }
                }
            }
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "ScreenRecorder", code: -7,
                                           userInfo: [NSLocalizedDescriptionKey: "M4A 変換に失敗"])
        }
    }

    private func convertAudioToMP3(from src: URL, to dst: URL) async throws {
        let asset = AVAsset(url: src)

        // AVAssetReader: PCM で読み出し
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "音声読み込みの初期化に失敗しました: \(error.localizedDescription)"]))
        }

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "音声トラックが見つかりません"]))
        }

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        guard reader.canAdd(readerOutput) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "音声読み込み出力の追加に失敗しました"]))
        }
        reader.add(readerOutput)

        // 元の音声のサンプルレートとチャンネル数を取得
        let sampleRate: Double
        let channelCount: Int
        if let formatDescriptions = try? await audioTrack.load(.formatDescriptions),
           let formatDesc = formatDescriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            sampleRate = asbd.pointee.mSampleRate
            channelCount = max(Int(asbd.pointee.mChannelsPerFrame), 1)
        } else {
            sampleRate = 48000
            channelCount = 2
        }

        // AVAssetWriter: MP3 で書き込み
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: dst, fileType: .mp3)
        } catch {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "MP3 書き込みの初期化に失敗しました: \(error.localizedDescription)"]))
        }

        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEGLayer3,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: min(channelCount, 2),
            AVEncoderBitRateKey: 192_000
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        guard writer.canAdd(writerInput) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -5,
                                    userInfo: [NSLocalizedDescriptionKey: "MP3 書き込み入力の追加に失敗しました"]))
        }
        writer.add(writerInput)

        // 読み書き開始
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // サンプルバッファを転送
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "screen.mp3.convert")) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }

        // 書き込み完了を待機
        await writer.finishWriting()

        guard writer.status == .completed else {
            let msg = writer.error?.localizedDescription ?? "不明なエラー"
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -6,
                                    userInfo: [NSLocalizedDescriptionKey: "MP3 変換に失敗しました: \(msg)"]))
        }

        guard reader.status == .completed else {
            let msg = reader.error?.localizedDescription ?? "不明なエラー"
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "ScreenRecorder", code: -6,
                                    userInfo: [NSLocalizedDescriptionKey: "音声読み込みに失敗しました: \(msg)"]))
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in self?.delegate?.recorderDidFail(with: error) }
        lock.lock(); isRecording = false; lock.unlock()
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }

        lock.lock()
        let vW = videoWriter; let vvI = videoVideoInput
        var vaI = videoAudioInput; let vaInit = videoAudioInitialized
        let vS = videoSessionStarted
        let aW = audioWriter; var aoI = audioOnlyInput
        let aoInit = audioOnlyInitialized; let aS = audioSessionStarted
        lock.unlock()

        let ts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        switch type {
        case .screen:
            guard let vW = vW, vW.status == .writing else { return }
            if !vS { vW.startSession(atSourceTime: ts); lock.lock(); videoSessionStarted = true; lock.unlock() }
            if let vvI = vvI, vvI.isReadyForMoreMediaData { vvI.append(sampleBuffer) }
            // プレビューフレームを更新（10フレームに1回）
            if let imageBuffer = sampleBuffer.imageBuffer {
                let ciImage = CIImage(cvPixelBuffer: imageBuffer)
                let context = CIContext()
                if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                    lock.lock(); latestPreviewFrame = cgImage; lock.unlock()
                }
            }

        case .audio:
            // 音声レベルを通知
            let level = calculateAudioLevel(from: sampleBuffer)
            Task { @MainActor [weak self] in self?.delegate?.recorderDidUpdateLevel(level) }

            // 動画 Writer の音声入力（パススルー遅延初期化）
            if !vaInit, let vW = vW, vW.status == .writing {
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                i.expectsMediaDataInRealTime = true
                if vW.canAdd(i) { vW.add(i); lock.lock(); videoAudioInput = i; videoAudioInitialized = true; lock.unlock(); vaI = i }
            }
            // 音声専用 Writer（パススルー遅延初期化）
            if !aoInit, let aW = aW, aW.status == .writing {
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                i.expectsMediaDataInRealTime = true
                if aW.canAdd(i) { aW.add(i); lock.lock(); audioOnlyInput = i; audioOnlyInitialized = true; lock.unlock(); aoI = i }
            }

            if let vW = vW, vW.status == .writing {
                if !vS { vW.startSession(atSourceTime: ts); lock.lock(); videoSessionStarted = true; lock.unlock() }
                if let vaI = vaI, vaI.isReadyForMoreMediaData { vaI.append(sampleBuffer) }
            }
            if let aW = aW, aW.status == .writing {
                if !aS { aW.startSession(atSourceTime: ts); lock.lock(); audioSessionStarted = true; lock.unlock() }
                if let aoI = aoI, aoI.isReadyForMoreMediaData { aoI.append(sampleBuffer) }
            }

        @unknown default: break
        }
    }

    private nonisolated func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let buf = sampleBuffer.dataBuffer else { return 0 }
        var len = 0; var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(buf, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr) == noErr,
              let p = ptr, len > 0 else { return 0 }
        if let fd = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd),
           asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            let count = len / MemoryLayout<Float32>.size
            guard count > 0 else { return 0 }
            var sum: Float = 0
            p.withMemoryRebound(to: Float32.self, capacity: count) { s in
                for i in 0..<count { sum += s[i] * s[i] }
            }
            return min(max(sqrt(sum / Float(count)) * 3.0, 0), 1.0)
        }
        let count = len / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        var sum: Float = 0
        p.withMemoryRebound(to: Int16.self, capacity: count) { s in
            for i in 0..<count { let v = Float(s[i]) / Float(Int16.max); sum += v * v }
        }
        return min(max(sqrt(sum / Float(count)) * 3.0, 0), 1.0)
    }
}
