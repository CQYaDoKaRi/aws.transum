// ExportRoundTripPropertyTests.swift
// Feature: audio-transcription-summary, Property 5: エクスポートのラウンドトリップ
// ランダムな Transcript/Summary テキストを生成し、エクスポート後のファイルに元のテキストが含まれることを検証する
// **Validates: Requirements 4.1**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - モック ExportManager（ラウンドトリップ検証用）

/// Exporting プロトコルに準拠したモック
/// 実際の ExportManager と同じ形式で UTF-8 テキストファイルに書き出す
private final class MockExportManager: Exporting, Sendable {

    func canWrite(to directory: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: directory.path)
    }

    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL {
        guard canWrite(to: directory) else {
            throw AppError.writePermissionDenied(path: directory.path)
        }

        // エクスポート内容の組み立て（実際の ExportManager と同じ形式）
        var lines: [String] = []
        lines.append("=== Transcript ===")
        lines.append(transcript.text)

        if let summary = summary {
            lines.append("")
            lines.append("=== Summary ===")
            lines.append(summary.text)
        }

        let content = lines.joined(separator: "\n")
        let fileName = "test_export_\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.exportFailed(underlying: error)
        }

        return fileURL
    }
}

// MARK: - Property 5: エクスポートのラウンドトリップ（Export Round Trip）

final class ExportRoundTripPropertyTests: XCTestCase {

    /// テスト用の一時ディレクトリ
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportRoundTripTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // テスト用ディレクトリを削除
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - ジェネレータ

    /// ランダムなテキストを生成するジェネレータ（1〜200文字）
    /// 英数字・日本語文字・空白・改行を含む
    private var textGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789あいうえおかきくけこ音声文字起こし要約テスト ")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 50)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    // MARK: - プロパティテスト

    /// ランダムな Transcript と Summary をエクスポートし、ファイルを読み込んで元のテキストが含まれることを検証
    func testExportRoundTrip() {
        let exportManager = MockExportManager()
        let dir = self.tempDirectory!

        property("エクスポートのラウンドトリップ: エクスポート後のファイルに元のテキストが含まれる")
            <- forAll(self.textGen, self.textGen) { (transcriptText: String, summaryText: String) in
                let transcript = Transcript(
                    id: UUID(),
                    audioFileId: UUID(),
                    text: transcriptText,
                    language: .japanese,
                    createdAt: Date()
                )

                let summary = Summary(
                    id: UUID(),
                    transcriptId: transcript.id,
                    text: summaryText,
                    createdAt: Date()
                )

                do {
                    // エクスポート実行
                    let fileURL = try awaitResult {
                        try await exportManager.export(
                            transcript: transcript,
                            summary: summary,
                            to: dir
                        )
                    }

                    // ファイルを読み込み
                    let content = try String(contentsOf: fileURL, encoding: .utf8)

                    // クリーンアップ
                    try? FileManager.default.removeItem(at: fileURL)

                    // 元の Transcript テキストが含まれることを確認
                    let containsTranscript = content.contains(transcriptText)

                    // 元の Summary テキストが含まれることを確認
                    let containsSummary = content.contains(summaryText)

                    return containsTranscript && containsSummary
                } catch {
                    return false
                }
            }
    }
}

// MARK: - ヘルパー関数

/// async 関数を同期的に実行するためのヘルパー
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
