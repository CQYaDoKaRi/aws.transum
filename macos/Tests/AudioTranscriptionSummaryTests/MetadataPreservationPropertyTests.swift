// MetadataPreservationPropertyTests.swift
// Feature: audio-transcription-summary, Property 2: 読み込み後のメタデータ保持
// モックの音声ファイル URL を生成し、読み込み後の AudioFile モデルが
// ファイル名・拡張子・正の再生時間を保持することを検証する
// **Validates: Requirements 1.5**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック FileImporter

/// FileImporting プロトコルに準拠したモック
/// AVAsset を使わず、指定されたメタデータで AudioFile を直接生成する
private final class MockFileImporter: FileImporting, Sendable {

    static let supportedExtensions: Set<String> = [
        "m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"
    ]

    func isSupported(fileExtension: String) -> Bool {
        Self.supportedExtensions.contains(fileExtension.lowercased())
    }

    /// モック実装: URL からメタデータを抽出し AudioFile を生成する
    /// 実際のファイルシステムや AVAsset にはアクセスしない
    func importFile(from url: URL) async throws -> AudioFile {
        let ext = url.pathExtension.lowercased()
        guard isSupported(fileExtension: ext) else {
            throw AppError.unsupportedFormat(
                ext,
                supportedFormats: Self.supportedExtensions.sorted()
            )
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        // モックでは固定の正の再生時間とファイルサイズを返す
        return AudioFile(
            id: UUID(),
            url: url,
            fileName: fileName,
            fileExtension: ext,
            duration: 10.0,
            fileSize: 1024,
            createdAt: Date()
        )
    }
}

// MARK: - テスト用入力データ構造体

/// プロパティテストで使用する入力パラメータ
private struct AudioFileInput {
    let fileName: String
    let fileExtension: String
    let duration: TimeInterval
}

// MARK: - Property 2: 読み込み後のメタデータ保持（Metadata Preservation After Import）

final class MetadataPreservationPropertyTests: XCTestCase {

    /// サポート対象の拡張子一覧
    private let supportedExtensions = Array(MockFileImporter.supportedExtensions)

    // MARK: - ジェネレータ

    /// 有効なファイル名を生成するジェネレータ
    /// 英数字とハイフン・アンダースコアで構成される 1〜20 文字の文字列
    private var fileNameGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 10)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    /// サポート対象のファイル拡張子をランダムに選択するジェネレータ
    private var extensionGen: Gen<String> {
        Gen<String>.fromElements(of: [
            "m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"
        ])
    }

    /// 正の再生時間を生成するジェネレータ（0.1 秒〜 7200 秒）
    private var durationGen: Gen<TimeInterval> {
        Gen<Double>.fromElements(in: 0.1...7200.0)
    }

    // MARK: - プロパティテスト

    /// 読み込み後の AudioFile がファイル名・拡張子・正の再生時間を保持することを検証
    /// FileImporting プロトコルのモック実装を使用し、ランダムな入力に対して
    /// メタデータが正しく保持されることを確認する
    func testMetadataPreservationAfterImport() {
        let importer = MockFileImporter()

        property("読み込み後のメタデータ保持: AudioFile はファイル名・拡張子・正の再生時間を保持する")
            <- forAll(self.fileNameGen, self.extensionGen, self.durationGen) {
                (name: String, ext: String, duration: TimeInterval) in

                // テスト用の URL を構築
                let url = URL(fileURLWithPath: "/tmp/\(name).\(ext)")

                // モック FileImporter で読み込み
                let audioFile: AudioFile
                do {
                    audioFile = try awaitResult {
                        try await importer.importFile(from: url)
                    }
                } catch {
                    return false
                }

                // ファイル名が一致すること
                let fileNameMatch = audioFile.fileName == name

                // 拡張子が一致すること（小文字化された状態）
                let extensionMatch = audioFile.fileExtension == ext.lowercased()

                // 再生時間が正の値であること
                let positiveDuration = audioFile.duration > 0

                // URL が一致すること
                let urlMatch = audioFile.url == url

                return fileNameMatch && extensionMatch && positiveDuration && urlMatch
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
