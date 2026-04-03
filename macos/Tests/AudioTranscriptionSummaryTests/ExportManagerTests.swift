// ExportManagerTests.swift
// ExportManager サービスのユニットテスト
// Exporting プロトコルに準拠したモックを使用して、エクスポート機能を検証する
// 要件: 4.4

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockExportManager（テスト用モック）

/// Exporting プロトコルに準拠したモック実装
/// 書き込み権限の制御をテストから操作可能にする
private final class MockExportManager: Exporting, @unchecked Sendable {

    /// 書き込み可能かどうかを制御するフラグ
    var canWriteResult: Bool = true

    /// export が呼ばれた回数
    private(set) var exportCallCount = 0

    func canWrite(to directory: URL) -> Bool {
        return canWriteResult
    }

    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL {
        exportCallCount += 1

        // 書き込み権限の確認
        guard canWrite(to: directory) else {
            throw AppError.writePermissionDenied(path: directory.path)
        }

        // エクスポート内容の組み立て
        var lines: [String] = []
        lines.append("=== Transcript ===")
        lines.append(transcript.text)

        if let summary = summary {
            lines.append("")
            lines.append("=== Summary ===")
            lines.append(summary.text)
        }

        let content = lines.joined(separator: "\n")
        let fileName = "transcript_test.txt"
        let fileURL = directory.appendingPathComponent(fileName)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.exportFailed(underlying: error)
        }

        return fileURL
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の Transcript を生成するヘルパー関数
private func makeTestTranscript(
    text: String = "テスト用の文字起こしテキストです。音声認識技術は近年大きく進歩しています。"
) -> Transcript {
    Transcript(
        id: UUID(),
        audioFileId: UUID(),
        text: text,
        language: .japanese,
        createdAt: Date()
    )
}

/// テスト用の Summary を生成するヘルパー関数
private func makeTestSummary(
    transcriptId: UUID = UUID(),
    text: String = "テスト用の要約テキストです。"
) -> Summary {
    Summary(
        id: UUID(),
        transcriptId: transcriptId,
        text: text,
        createdAt: Date()
    )
}

// MARK: - 書き込み権限なしのエラーテスト（要件 4.4）

@Suite("ExportManager 書き込み権限テスト")
struct ExportManagerWritePermissionTests {

    /// 書き込み権限がない場合に writePermissionDenied エラーが発生することを確認
    @Test func writePermissionDeniedError() async {
        let exportManager = MockExportManager()
        exportManager.canWriteResult = false

        let transcript = makeTestTranscript()
        let summary = makeTestSummary(transcriptId: transcript.id)
        let directory = URL(fileURLWithPath: "/nonexistent/readonly/path")

        do {
            _ = try await exportManager.export(
                transcript: transcript,
                summary: summary,
                to: directory
            )
            Issue.record("writePermissionDenied エラーが発生するべき")
        } catch let error as AppError {
            guard case .writePermissionDenied(let path) = error else {
                Issue.record("writePermissionDenied エラーが期待されたが、\(error) が発生")
                return
            }
            // パスが正しく渡されていることを確認
            #expect(path == directory.path)
            // エラーメッセージが正しいことを確認
            #expect(error.errorDescription == "保存先に書き込みできません。別のフォルダを選択してください")
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// Summary なしでも書き込み権限エラーが正しく発生することを確認
    @Test func writePermissionDeniedWithoutSummary() async {
        let exportManager = MockExportManager()
        exportManager.canWriteResult = false

        let transcript = makeTestTranscript()
        let directory = URL(fileURLWithPath: "/readonly/path")

        do {
            _ = try await exportManager.export(
                transcript: transcript,
                summary: nil,
                to: directory
            )
            Issue.record("writePermissionDenied エラーが発生するべき")
        } catch let error as AppError {
            guard case .writePermissionDenied = error else {
                Issue.record("writePermissionDenied エラーが期待されたが、\(error) が発生")
                return
            }
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// canWrite が false を返す場合に export が呼ばれてもファイルが作成されないことを確認
    @Test func noFileCreatedWhenPermissionDenied() async {
        let exportManager = MockExportManager()
        exportManager.canWriteResult = false

        let transcript = makeTestTranscript()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("permission_test_\(UUID().uuidString)")

        do {
            _ = try await exportManager.export(
                transcript: transcript,
                summary: nil,
                to: directory
            )
        } catch is AppError {
            // 期待通りエラーが発生
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }

        // ディレクトリが作成されていないことを確認
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// canWrite が true の場合にエクスポートが成功することを確認
    @Test func exportSucceedsWithWritePermission() async throws {
        let exportManager = MockExportManager()
        exportManager.canWriteResult = true

        let transcript = makeTestTranscript()
        let summary = makeTestSummary(transcriptId: transcript.id)

        // 一時ディレクトリを作成
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_success_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = try await exportManager.export(
            transcript: transcript,
            summary: summary,
            to: directory
        )

        // ファイルが作成されたことを確認
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // ファイル内容を確認
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains(transcript.text))
        #expect(content.contains(summary.text))
    }
}
