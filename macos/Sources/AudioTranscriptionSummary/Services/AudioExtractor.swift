// AudioExtractor.swift
// 動画ファイルから音声トラックを抽出するサービス
// AVAssetExportSession を使用して動画の音声を m4a ファイルとして書き出す

import AVFoundation
import Foundation

// MARK: - AudioExtractor

/// 動画ファイルから音声トラックを抽出し、音声ファイルとして保存するサービス
/// 文字起こし前に動画から音声のみを取り出す際に使用する
final class AudioExtractor: Sendable {

    /// 動画ファイルから音声を抽出し、一時ファイルとして保存する
    /// - Parameter videoFile: 音声を抽出する動画の AudioFile
    /// - Returns: 抽出された音声の AudioFile（m4a 形式）
    /// - Throws: 音声トラックが存在しない場合や抽出に失敗した場合
    func extractAudio(from videoFile: AudioFile) async throws -> AudioFile {
        let asset = AVAsset(url: videoFile.url)

        // 音声トラックの存在を確認
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "AudioExtractor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "動画に音声トラックが含まれていません"]
                )
            )
        }

        // 一時ファイルの出力先を準備
        let tempDir = FileManager.default.temporaryDirectory
        let outputFileName = "\(videoFile.fileName)_audio_\(UUID().uuidString).m4a"
        let outputURL = tempDir.appendingPathComponent(outputFileName)

        // 既存ファイルがあれば削除
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // AVAssetExportSession で音声のみをエクスポート
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "AudioExtractor",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "音声エクスポートセッションの作成に失敗しました"]
                )
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // エクスポート実行
        await exportSession.export()

        guard exportSession.status == .completed else {
            let errorMessage = exportSession.error?.localizedDescription ?? "不明なエラー"
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "AudioExtractor",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "音声の抽出に失敗しました: \(errorMessage)"]
                )
            )
        }

        // 抽出された音声ファイルの情報を取得
        let outputAsset = AVAsset(url: outputURL)
        let duration = try await CMTimeGetSeconds(outputAsset.load(.duration))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        return AudioFile(
            id: UUID(),
            url: outputURL,
            fileName: videoFile.fileName,
            fileExtension: "m4a",
            duration: duration,
            fileSize: fileSize,
            createdAt: Date()
        )
    }
}
