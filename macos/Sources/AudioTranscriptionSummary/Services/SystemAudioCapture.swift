// SystemAudioCapture.swift
// PC のシステム音声をキャプチャするサービス
// ScreenCaptureKit で取得した音声をパススルーで一時ファイルに保存し、
// 停止後に AVAssetReader + AVAssetWriter で MP3 に変換する

import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine

@MainActor
protocol SystemAudioCaptureDelegate: AnyObject {
    func captureDidStart()
    func captureDidStop()
    func captureDidFail(with error: Error)
    func captureDidUpdateLevel(_ level: Float)
}

final class SystemAudioCapture: NSObject, @unchecked Sendable {

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private(set) var isCapturing: Bool = false
    private var finalFileURL: URL? // 最終保存先ファイル
    weak var delegate: (any SystemAudioCaptureDelegate)?
    /// リアルタイム文字起こし用の音声バッファ転送コールバック
    /// 録音中の CMSampleBuffer を RealtimeTranscriptionViewModel に転送する
    var onAudioBufferForRealtime: (@Sendable (CMSampleBuffer) -> Void)?
    private var captureStartTime: Date?
    private let lock = NSLock()
    private var sessionStarted = false

    /// マイク録音用の AVCaptureSession
    private var captureSession: AVCaptureSession?
    /// マイク録音用の AVCaptureAudioDataOutput
    private var captureOutput: AVCaptureAudioDataOutput?
    /// 現在の音源種別（マイクかシステム音声かの判定に使用）
    private var currentSourceType: AudioSourceType = .systemAudio

    /// プレビューモニタリング中かどうか（録音せずにレベルのみ取得）
    private(set) var isMonitoring: Bool = false
    /// プレビュー用の AVCaptureSession（マイク）
    private var monitorSession: AVCaptureSession?
    /// プレビュー用の SCStream（システム音声）
    private var monitorStream: SCStream?

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - キャプチャ開始

    /// 指定された音源でキャプチャを開始する
    /// - Parameter sourceType: 音源種別（デフォルト: システム全体）
    func startCapture(sourceType: AudioSourceType = .systemAudio) async throws {
        guard !isCapturing else { return }
        currentSourceType = sourceType

        let saveDir = AWSSettingsViewModel.recordingDirectory
        if !FileManager.default.fileExists(atPath: saveDir.path) {
            try FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        }
        let dateStr = Self.fileNameFormatter.string(from: Date())
        // 最終保存先に直接書き込む（一時ファイルを経由しない）
        let finalM4A = saveDir.appendingPathComponent("\(dateStr).m4a")
        finalFileURL = finalM4A

        // AVAssetWriter を準備（AAC で直接 M4A に書き込み）
        let writer = try AVAssetWriter(outputURL: finalM4A, fileType: .m4a)
        // AAC エンコード設定で AVAssetWriterInput を事前に作成
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        assetWriter = writer
        audioInput = input
        sessionStarted = false

        // isCapturing を先に true にする（SCStreamOutput コールバックが書き込みを開始できるように）
        isCapturing = true
        captureStartTime = Date()

        if sourceType.isMicrophone {
            await stopMonitoring()
            try startMicrophoneCapture(sourceType: sourceType)
        } else {
            // モニタリングを停止して新しい SCStream を作成
            await stopMonitoring()
            // ScreenCaptureKit のリソース解放を待つ（2秒に延長）
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Writer が準備完了していることを確認
            guard let w = assetWriter, w.status == .writing else {
                throw AppError.transcriptionFailed(
                    underlying: NSError(domain: "SystemAudioCapture", code: -9,
                                        userInfo: [NSLocalizedDescriptionKey: "録音の初期化に失敗しました。もう一度お試しください。"]))
            }

            try await startScreenCapture(sourceType: sourceType)

            // ストリーム開始後、最初のサンプルが届くまで少し待つ
            try? await Task.sleep(nanoseconds: 500_000_000)

            // ストリームが正常に開始されたか確認
            guard stream != nil else {
                throw AppError.transcriptionFailed(
                    underlying: NSError(domain: "SystemAudioCapture", code: -9,
                                        userInfo: [NSLocalizedDescriptionKey: "システム音声のキャプチャ開始に失敗しました。画面収録の権限を確認してください。"]))
            }
        }

        await MainActor.run { [weak self] in self?.delegate?.captureDidStart() }
    }

    /// マイク録音を開始する（AVCaptureSession）
    private func startMicrophoneCapture(sourceType: AudioSourceType) throws {
        guard case .microphone(let deviceID, _) = sourceType else { return }

        // マイクアクセス権限を確認
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            // 権限リクエストは同期的に待てないため、事前に許可が必要
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -14,
                                    userInfo: [NSLocalizedDescriptionKey: "マイクへのアクセスを許可してください。「システム設定 > プライバシーとセキュリティ > マイク」でこのアプリを許可してください。"]))
        default:
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -14,
                                    userInfo: [NSLocalizedDescriptionKey: "マイクへのアクセスが拒否されています。「システム設定 > プライバシーとセキュリティ > マイク」でこのアプリを許可してください。"]))
        }

        guard let device = AVCaptureDevice(uniqueID: deviceID) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -11,
                                    userInfo: [NSLocalizedDescriptionKey: "マイクデバイスが見つかりません"]))
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -12,
                                    userInfo: [NSLocalizedDescriptionKey: "マイク入力の追加に失敗しました"]))
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "mic.capture", qos: .userInitiated))
        guard session.canAddOutput(output) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -13,
                                    userInfo: [NSLocalizedDescriptionKey: "マイク出力の追加に失敗しました"]))
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
        captureSession = session
        captureOutput = output
    }

    /// システム音声 / アプリ音声のキャプチャを開始する（ScreenCaptureKit）
    private func startScreenCapture(sourceType: AudioSourceType) async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -10,
                                    userInfo: [NSLocalizedDescriptionKey: "画面収録の権限が必要です。「システム設定 > プライバシーとセキュリティ > 画面収録とシステム音声」でこのアプリ（またはターミナル）を許可してください。"]))
        }
        guard let display = content.displays.first else {
            throw AppError.transcriptionFailed(
                underlying: NSError(domain: "SystemAudioCapture", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "ディスプレイが見つかりません"]))
        }

        let filter: SCContentFilter
        switch sourceType {
        case .application(let bundleID, _):
            // 特定アプリの音声: includingApplications フィルターを使用
            if let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) {
                filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }
        default:
            // システム全体: 全アプリの音声をキャプチャ
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.width = 2; config.height = 2; config.showsCursor = false
        config.capturesAudio = true; config.sampleRate = 48000; config.channelCount = 2
        config.excludesCurrentProcessAudio = false

        let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
        try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        try await captureStream.startCapture()

        stream = captureStream
    }

    // MARK: - キャプチャ停止

    func stopCapture() async throws -> AudioFile {
        guard isCapturing else {
            throw NSError(domain: "SystemAudioCapture", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "キャプチャが開始されていません"])
        }

        // マイク録音の場合は AVCaptureSession を停止、SCStream は触らない
        if currentSourceType.isMicrophone {
            captureSession?.stopRunning()
            captureSession = nil; captureOutput = nil
        } else {
            // システム音声の場合は SCStream を停止
            if let s = stream {
                do { try await s.stopCapture() } catch { /* 既に停止済みの場合は無視 */ }
            }
        }
        stream = nil
        audioInput?.markAsFinished()

        if let writer = assetWriter {
            await writer.finishWriting()
        }
        isCapturing = false
        await MainActor.run { [weak self] in self?.delegate?.captureDidStop() }

        guard let finalM4A = finalFileURL else {
            let err = NSError(domain: "SystemAudioCapture", code: -5,
                              userInfo: [NSLocalizedDescriptionKey: "録音ファイルのパスが設定されていません"])
            ErrorLogger.saveErrorLog(error: err, operation: "録音保存", context: ["finalFileURL": finalFileURL?.path ?? "nil"])
            throw err
        }

        let fileExists = FileManager.default.fileExists(atPath: finalM4A.path)
        let fileAttrs = try? FileManager.default.attributesOfItem(atPath: finalM4A.path)
        let fileSize = fileAttrs?[.size] as? Int64 ?? 0

        guard fileExists, fileSize > 0 else {
            try? FileManager.default.removeItem(at: finalM4A)
            assetWriter = nil; audioInput = nil

            let err = NSError(domain: "SystemAudioCapture", code: -8,
                              userInfo: [NSLocalizedDescriptionKey: "音声データが検出されませんでした。録音中に音声が再生されていたか確認してください。"])
            ErrorLogger.saveErrorLog(
                error: err,
                operation: "録音_音声データなし",
                context: ["finalM4A": finalM4A.path, "size": "0", "sourceType": "\(currentSourceType)"])
            throw AppError.transcriptionFailed(underlying: err)
        }

        let duration = Date().timeIntervalSince(captureStartTime ?? Date())
        let audioFile = AudioFile(id: UUID(), url: finalM4A, fileName: finalM4A.deletingPathExtension().lastPathComponent,
                                  fileExtension: "m4a", duration: duration, fileSize: fileSize, createdAt: Date())
        assetWriter = nil; audioInput = nil
        return audioFile
    }

    // MARK: - キャンセル

    func cancelCapture() async {
        if currentSourceType.isMicrophone {
            captureSession?.stopRunning()
            captureSession = nil; captureOutput = nil
        } else {
            if let s = stream { try? await s.stopCapture() }
        }
        stream = nil
        audioInput?.markAsFinished()
        await assetWriter?.finishWriting()
        if let url = finalFileURL { try? FileManager.default.removeItem(at: url) }
        isCapturing = false
        assetWriter = nil; audioInput = nil; finalFileURL = nil
        await MainActor.run { [weak self] in self?.delegate?.captureDidStop() }
    }

    // MARK: - プレビューモニタリング（録音せずにレベルのみ取得）

    /// 指定された音源の入力レベルをモニタリング開始する（録音はしない）
    func startMonitoring(sourceType: AudioSourceType) async {
        await stopMonitoring()

        if sourceType.isMicrophone {
            guard case .microphone(let deviceID, _) = sourceType,
                  let device = AVCaptureDevice(uniqueID: deviceID) else { return }
            let session = AVCaptureSession()
            session.beginConfiguration()
            guard let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "monitor.mic", qos: .userInitiated))
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            monitorSession = session
            isMonitoring = true
        } else {
            // システム音声 / アプリ音声: ScreenCaptureKit でモニタリング
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else { return }

                let filter: SCContentFilter
                if case .application(let bundleID, _) = sourceType,
                   let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) {
                    filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
                } else {
                    filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                }

                let config = SCStreamConfiguration()
                config.width = 2; config.height = 2; config.showsCursor = false
                config.capturesAudio = true; config.sampleRate = 48000; config.channelCount = 2
                config.excludesCurrentProcessAudio = false

                let s = SCStream(filter: filter, configuration: config, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                try await s.startCapture()
                monitorStream = s
                isMonitoring = true
            } catch {
                // 権限エラー等は無視（プレビューなので）
            }
        }
    }

    /// プレビューモニタリングを停止する
    func stopMonitoring() async {
        monitorSession?.stopRunning()
        monitorSession = nil
        if let s = monitorStream { try? await s.stopCapture() }
        monitorStream = nil
        isMonitoring = false
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in self?.delegate?.captureDidFail(with: error) }
        lock.lock(); isCapturing = false; lock.unlock()
    }
}

// MARK: - SCStreamOutput

extension SystemAudioCapture: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, sampleBuffer.isValid else { return }

        // 音声レベルを常に通知（モニタリング中も録音中も）
        let level = calculateAudioLevel(from: sampleBuffer)
        Task { @MainActor [weak self] in self?.delegate?.captureDidUpdateLevel(level) }

        // 録音中でなければ（モニタリングのみ）ここで終了
        lock.lock()
        let writer = assetWriter
        let input = audioInput
        let started = sessionStarted
        let capturing = isCapturing
        lock.unlock()

        // キャプチャ中でなければ書き込みしない（モニタリングのみ）
        guard capturing else { return }

        guard let writer = writer, writer.status == .writing else { return }

        // セッション開始（最初のサンプルのタイムスタンプで開始）
        if !started {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            lock.lock(); sessionStarted = true; lock.unlock()
        }

        if let input = input, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }

        // リアルタイム文字起こし用に音声バッファを転送（録音処理に影響を与えない）
        onAudioBufferForRealtime?(sampleBuffer)
    }

    private nonisolated func calculateAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        guard let buf = sampleBuffer.dataBuffer else { return 0 }
        var len = 0; var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(buf, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr) == noErr,
              let p = ptr, len > 0 else { return 0 }

        // フォーマットに応じて RMS を計算
        // ScreenCaptureKit: Float32, マイク: Int16 の場合がある
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                // Float32
                let count = len / MemoryLayout<Float32>.size
                guard count > 0 else { return 0 }
                var sum: Float = 0
                p.withMemoryRebound(to: Float32.self, capacity: count) { s in
                    for i in 0..<count { sum += s[i] * s[i] }
                }
                return min(max(sqrt(sum / Float(count)) * 3.0, 0), 1.0)
            }
        }

        // Int16（マイクのデフォルト）
        let count = len / MemoryLayout<Int16>.size
        guard count > 0 else { return 0 }
        var sum: Float = 0
        p.withMemoryRebound(to: Int16.self, capacity: count) { s in
            for i in 0..<count {
                let sample = Float(s[i]) / Float(Int16.max)
                sum += sample * sample
            }
        }
        return min(max(sqrt(sum / Float(count)) * 3.0, 0), 1.0)
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate（マイク録音用）

extension SystemAudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }

        // 音声レベルを常に通知（モニタリング中も録音中も）
        let level = calculateAudioLevel(from: sampleBuffer)
        Task { @MainActor [weak self] in self?.delegate?.captureDidUpdateLevel(level) }

        // 録音中でなければ（モニタリングのみ）ここで終了
        lock.lock()
        let writer = assetWriter
        let input = audioInput
        let started = sessionStarted
        lock.unlock()

        guard let writer = writer, writer.status == .writing else { return }

        if !started {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            lock.lock(); sessionStarted = true; lock.unlock()
        }

        if let input = input, input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }

        // リアルタイム文字起こし用に音声バッファを転送
        onAudioBufferForRealtime?(sampleBuffer)
    }
}
