// FileFormatValidationPropertyTests.swift
// Feature: audio-transcription-summary, Property 1: ファイル形式の判定整合性
// ランダムなファイル拡張子文字列を生成し、サポート対象形式との判定整合性を検証する
// **Validates: Requirements 1.3, 1.4**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - Property 1: ファイル形式の判定整合性（File Format Validation Consistency）

final class FileFormatValidationPropertyTests: XCTestCase {

    /// サポート対象の拡張子一覧
    private let supportedExtensions: Set<String> = [
        "m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"
    ]

    // MARK: - ランダム拡張子ジェネレータ

    /// ランダムなファイル拡張子文字列を生成するジェネレータ
    /// サポート対象形式・大文字バリエーション・ランダム文字列・既知の非対応形式を混合
    private var fileExtensionGen: Gen<String> {
        // サポート対象形式をそのまま生成
        let supportedGen = Gen<String>.fromElements(of: Array(supportedExtensions))
        // 大文字バリエーション（例: "M4a", "WAV"）
        let uppercaseSupportedGen = supportedGen.map { ext in
            String(ext.enumerated().map { index, char in
                index % 2 == 0 ? Character(char.uppercased()) : char
            })
        }
        // ランダムな英字文字列（4文字固定）
        let randomAlphaGen = Gen<Character>.fromElements(
            of: Array("abcdefghijklmnopqrstuvwxyz")
        )
        .proliferate(withSize: 4)
        .map { String($0) }
        .suchThat { !$0.isEmpty }
        // サポート対象外の既知形式
        let unsupportedKnownGen = Gen<String>.fromElements(of: [
            "flac", "ogg", "wma", "avi", "mkv",
            "webm", "txt", "pdf", "doc"
        ])

        return Gen<String>.one(of: [
            supportedGen,
            uppercaseSupportedGen,
            randomAlphaGen,
            unsupportedKnownGen,
        ])
    }

    // MARK: - プロパティテスト

    /// isSupported の判定がサポート対象形式リストと整合していることを検証
    /// 任意のファイル拡張子に対して:
    /// - サポート対象拡張子（大文字小文字問わず）→ true を返す
    /// - サポート対象外拡張子 → false を返す
    func testFileFormatValidationConsistency() {
        let fileImporter = FileImporter()

        property("ファイル形式の判定整合性: isSupported はサポート対象形式と整合する")
            <- forAll(self.fileExtensionGen) { (ext: String) in
                let result = fileImporter.isSupported(fileExtension: ext)
                let expected = self.supportedExtensions.contains(
                    ext.lowercased()
                )
                return result == expected
            }
    }

    /// サポート対象外の拡張子でのエラーメッセージにすべてのサポート対象形式が含まれることを検証
    /// FileImporter.importFile は unsupportedFormat エラーで supportedExtensions.sorted() を渡す
    /// そのエラーの errorDescription にすべてのサポート対象形式が含まれることを確認する
    func testUnsupportedFormatErrorContainsAllSupportedFormats() {
        // サポート対象外の拡張子のみを生成するジェネレータ
        let unsupportedGen = Gen<String>.fromElements(of: [
            "flac", "ogg", "wma", "avi", "mkv",
            "webm", "txt", "pdf", "doc", "zip", "rar"
        ])

        property("サポート対象外形式のエラーメッセージにすべてのサポート対象形式が含まれる")
            <- forAll(unsupportedGen) { (ext: String) in
                // FileImporter の実装と同じ方法でエラーを構築
                // importFile 内部: AppError.unsupportedFormat(ext, supportedFormats: Self.supportedExtensions.sorted())
                let sortedFormats = FileImporter.supportedExtensions.sorted()
                let error = AppError.unsupportedFormat(
                    ext.lowercased(),
                    supportedFormats: sortedFormats
                )

                guard let message = error.errorDescription else {
                    return false
                }

                // すべてのサポート対象形式がエラーメッセージに含まれること
                let allFormatsInMessage = self.supportedExtensions.allSatisfy {
                    message.contains($0)
                }

                // 入力拡張子がエラーメッセージに含まれること
                let extInMessage = message.contains(ext.lowercased())

                // supportedFormats 配列にすべてのサポート対象形式が含まれること
                let allFormatsInArray = self.supportedExtensions.allSatisfy {
                    sortedFormats.contains($0)
                }

                return allFormatsInMessage && extInMessage && allFormatsInArray
            }
    }
}
