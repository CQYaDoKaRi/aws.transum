// FileImporterTests.swift
// FileImporter サービスのユニットテスト
// サポート対象形式の判定、破損ファイルのエラーハンドリング、サポート対象外形式のエラーを検証する
// 要件: 1.1, 1.2, 1.3, 1.6

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - FileImporter isSupported テスト

@Suite("FileImporter isSupported テスト")
struct FileImporterIsSupportedTests {

    let importer = FileImporter()

    /// サポート対象の音声形式（m4a, wav, mp3, aiff）が true を返すことを確認
    @Test func supportedAudioFormats() {
        #expect(importer.isSupported(fileExtension: "m4a"))
        #expect(importer.isSupported(fileExtension: "wav"))
        #expect(importer.isSupported(fileExtension: "mp3"))
        #expect(importer.isSupported(fileExtension: "aiff"))
    }

    /// サポート対象の動画形式（mp4, mov, m4v）が true を返すことを確認
    @Test func supportedVideoFormats() {
        #expect(importer.isSupported(fileExtension: "mp4"))
        #expect(importer.isSupported(fileExtension: "mov"))
        #expect(importer.isSupported(fileExtension: "m4v"))
    }

    /// 大文字・混在ケースでもサポート対象と判定されることを確認
    @Test func caseInsensitiveMatching() {
        #expect(importer.isSupported(fileExtension: "M4A"))
        #expect(importer.isSupported(fileExtension: "WAV"))
        #expect(importer.isSupported(fileExtension: "Mp3"))
        #expect(importer.isSupported(fileExtension: "AIFF"))
        #expect(importer.isSupported(fileExtension: "MP4"))
        #expect(importer.isSupported(fileExtension: "MOV"))
        #expect(importer.isSupported(fileExtension: "M4V"))
    }

    /// サポート対象外の形式が false を返すことを確認
    @Test func unsupportedFormats() {
        #expect(!importer.isSupported(fileExtension: "flac"))
        #expect(!importer.isSupported(fileExtension: "ogg"))
        #expect(!importer.isSupported(fileExtension: "wma"))
        #expect(!importer.isSupported(fileExtension: "txt"))
        #expect(!importer.isSupported(fileExtension: "pdf"))
        #expect(!importer.isSupported(fileExtension: "avi"))
    }

    /// 空文字列が false を返すことを確認
    @Test func emptyExtension() {
        #expect(!importer.isSupported(fileExtension: ""))
    }
}

// MARK: - FileImporter supportedExtensions テスト

@Suite("FileImporter supportedExtensions テスト")
struct FileImporterSupportedExtensionsTests {

    /// supportedExtensions に全7形式が含まれることを確認
    @Test func containsAllFormats() {
        let expected: Set<String> = ["m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"]
        #expect(FileImporter.supportedExtensions == expected)
    }

    /// videoExtensions に動画形式のみが含まれることを確認
    @Test func videoExtensionsSubset() {
        let expectedVideo: Set<String> = ["mp4", "mov", "m4v"]
        #expect(FileImporter.videoExtensions == expectedVideo)
        // 動画形式はサポート対象形式のサブセットであること
        #expect(FileImporter.videoExtensions.isSubset(of: FileImporter.supportedExtensions))
    }
}

// MARK: - FileImporter importFile エラーハンドリングテスト

@Suite("FileImporter importFile エラーハンドリングテスト")
struct FileImporterImportFileTests {

    let importer = FileImporter()

    /// サポート対象外の拡張子で unsupportedFormat エラーが発生することを確認
    @Test func unsupportedFormatError() async {
        let url = URL(fileURLWithPath: "/tmp/test_file.flac")

        do {
            _ = try await importer.importFile(from: url)
            Issue.record("unsupportedFormat エラーが発生するべき")
        } catch let error as AppError {
            // unsupportedFormat エラーであることを確認
            guard case .unsupportedFormat(let ext, let supportedFormats) = error else {
                Issue.record("unsupportedFormat エラーが期待されたが、\(error) が発生")
                return
            }
            // 拡張子が正しく渡されていること
            #expect(ext == "flac")
            // サポート対象形式がすべて含まれていること
            let expectedFormats = FileImporter.supportedExtensions.sorted()
            #expect(supportedFormats == expectedFormats)
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// サポート対象外の拡張子のエラーメッセージに対応形式一覧が含まれることを確認
    @Test func unsupportedFormatErrorMessage() async {
        let url = URL(fileURLWithPath: "/tmp/test_file.txt")

        do {
            _ = try await importer.importFile(from: url)
            Issue.record("エラーが発生するべき")
        } catch let error as AppError {
            guard let message = error.errorDescription else {
                Issue.record("errorDescription が nil")
                return
            }
            // エラーメッセージに拡張子が含まれること
            #expect(message.contains("txt"))
            // エラーメッセージにすべてのサポート対象形式が含まれること
            for ext in FileImporter.supportedExtensions {
                #expect(message.contains(ext), "エラーメッセージに \(ext) が含まれるべき")
            }
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// 存在しないファイルパスで corruptedFile エラーが発生することを確認
    @Test func corruptedFileErrorForNonExistentFile() async {
        // サポート対象形式だが存在しないファイル
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).m4a")

        do {
            _ = try await importer.importFile(from: url)
            Issue.record("corruptedFile エラーが発生するべき")
        } catch let error as AppError {
            guard case .corruptedFile = error else {
                Issue.record("corruptedFile エラーが期待されたが、\(error) が発生")
                return
            }
            // corruptedFile エラーのメッセージを確認
            #expect(error.errorDescription == "ファイルが読み込めません")
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// 各サポート対象形式で存在しないファイルが corruptedFile エラーを返すことを確認
    @Test func corruptedFileErrorForAllSupportedFormats() async {
        let extensions = ["m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"]

        for ext in extensions {
            let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).\(ext)")

            do {
                _ = try await importer.importFile(from: url)
                Issue.record("\(ext) 形式で corruptedFile エラーが発生するべき")
            } catch let error as AppError {
                guard case .corruptedFile = error else {
                    Issue.record("\(ext) 形式で corruptedFile エラーが期待されたが、\(error) が発生")
                    continue
                }
                // 正常: corruptedFile エラーが発生
            } catch {
                Issue.record("\(ext) 形式で AppError が期待されたが、\(error) が発生")
            }
        }
    }

    /// 大文字拡張子のサポート対象外ファイルで unsupportedFormat エラーが発生することを確認
    @Test func unsupportedFormatCaseInsensitive() async {
        let url = URL(fileURLWithPath: "/tmp/test_file.FLAC")

        do {
            _ = try await importer.importFile(from: url)
            Issue.record("unsupportedFormat エラーが発生するべき")
        } catch let error as AppError {
            guard case .unsupportedFormat = error else {
                Issue.record("unsupportedFormat エラーが期待されたが、\(error) が発生")
                return
            }
            // 正常: unsupportedFormat エラーが発生
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }
}
