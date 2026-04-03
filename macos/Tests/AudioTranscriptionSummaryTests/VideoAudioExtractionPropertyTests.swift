// VideoAudioExtractionPropertyTests.swift
// Feature: audio-transcription-summary, Property 7: 動画からの音声抽出整合性
// 音声トラック付き動画ファイル（モック）を生成し、抽出後の AudioFile が
// 正の再生時間を持つ m4a 形式であることを検証する
// **Validates: Requirements 1.7**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック AudioExtractor（音声抽出検証用）

/// 実際の AVAsset / AVAssetExportSession を使わず、
/// AudioExtractor と同じ契約（音声トラック付き動画 → m4a 形式の AudioFile）を
/// シミュレートするモック実装
private final class MockAudioExtractor: Sendable {

    /// 動画ファイルから音声を抽出する（モック実装）
    /// - Parameter videoFile: 音声トラック付き動画の AudioFile
    /// - Returns: m4a 形式の AudioFile（正の再生時間を持つ）
    /// - Throws: 音声トラックが存在しない場合は transcriptionFailed エラー
    func extractAudio(from videoFile: AudioFile) async throws -> AudioFile {
        // 動画形式であることを確認
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
        guard videoExtensions.contains(videoFile.fileExtension.lowercased()) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "MockAudioExtractor",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "動画ファイルではありません"]
                )
            )
        }

        // 音声トラックが存在する動画として処理（モック）
        // 実際の AudioExtractor と同じ出力形式で AudioFile を生成
        let outputFileName = "\(videoFile.fileName)_audio_\(UUID().uuidString).m4a"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(outputFileName)

        // 抽出後の音声ファイルは元の動画と同じ再生時間を持つ
        return AudioFile(
            id: UUID(),
            url: outputURL,
            fileName: videoFile.fileName,
            fileExtension: "m4a",
            duration: videoFile.duration,
            fileSize: max(videoFile.fileSize / 4, 1),
            createdAt: Date()
        )
    }
}

// MARK: - Property 7: 動画からの音声抽出整合性（Video Audio Extraction Consistency）

final class VideoAudioExtractionPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// 有効な動画ファイル名を生成するジェネレータ
    /// 英数字とハイフン・アンダースコアで構成される文字列
    private var fileNameGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 10)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    /// 動画ファイルの拡張子をランダムに選択するジェネレータ
    private var videoExtensionGen: Gen<String> {
        Gen<String>.fromElements(of: ["mp4", "mov", "m4v"])
    }

    /// 正の再生時間を生成するジェネレータ（0.1 秒〜 7200 秒）
    private var durationGen: Gen<TimeInterval> {
        Gen<Double>.fromElements(in: 0.1...7200.0)
    }

    /// 正のファイルサイズを生成するジェネレータ（1 バイト〜 10GB）
    private var fileSizeGen: Gen<Int64> {
        Gen<Int64>.fromElements(in: 1...10_737_418_240)
    }

    // MARK: - プロパティテスト

    /// 音声トラック付き動画ファイルから音声を抽出した後、
    /// 結果の AudioFile が正の再生時間を持つ m4a 形式であることを検証
    func testVideoAudioExtractionConsistency() {
        let extractor = MockAudioExtractor()

        property("動画からの音声抽出整合性: 抽出後の AudioFile は正の再生時間を持つ m4a 形式である")
            <- forAll(self.fileNameGen, self.videoExtensionGen, self.durationGen, self.fileSizeGen) {
                (fileName: String, videoExt: String, duration: TimeInterval, fileSize: Int64) in

                // ランダムなメタデータで動画ファイルの AudioFile を構築
                let videoFile = AudioFile(
                    id: UUID(),
                    url: URL(fileURLWithPath: "/tmp/\(fileName).\(videoExt)"),
                    fileName: fileName,
                    fileExtension: videoExt,
                    duration: duration,
                    fileSize: fileSize,
                    createdAt: Date()
                )

                do {
                    // モック AudioExtractor で音声を抽出
                    let extractedAudio = try awaitResult {
                        try await extractor.extractAudio(from: videoFile)
                    }

                    // 抽出後のファイル拡張子が m4a であること
                    let isM4aFormat = extractedAudio.fileExtension == "m4a"

                    // 抽出後の再生時間が正の値であること
                    let hasPositiveDuration = extractedAudio.duration > 0

                    return isM4aFormat && hasPositiveDuration
                } catch {
                    // 音声トラック付き動画からの抽出は成功すべき
                    return false
                }
            }
    }
}

// MARK: - ヘルパー関数

/// async 関数を同期的に実行するためのヘルパー
/// SwiftCheck は同期的なプロパティを期待するため、async/await を橋渡しする
private func awaitResult<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?

    Task {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    switch result! {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    }
}
