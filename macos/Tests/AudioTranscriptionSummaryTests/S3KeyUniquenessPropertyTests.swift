// S3KeyUniquenessPropertyTests.swift
// Feature: amazon-transcribe-integration, Property 5: S3 キーの一意性と URI 形式
// ランダムな AudioFile とバケット名で S3 キーを生成し、UUID を含む正しい URI 形式であること、
// 複数回生成で重複しないことを検証する
// **Validates: Requirements 3.2, 3.5**

import XCTest
import SwiftCheck
@testable import AudioTranscriptionSummary

// MARK: - Property 5: S3 キーの一意性と URI 形式（S3 Key Uniqueness and URI Format）

final class S3KeyUniquenessPropertyTests: XCTestCase {

    // MARK: - ジェネレータ

    /// ランダムなファイル名を生成するジェネレータ
    private var fileNameGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 10)
            .map { String($0) }
            .suchThat { !$0.isEmpty }
    }

    /// ランダムなファイル拡張子を生成するジェネレータ
    private var extensionGen: Gen<String> {
        Gen<String>.fromElements(of: ["m4a", "wav", "mp3", "aac", "flac"])
    }

    /// ランダムなバケット名を生成するジェネレータ（S3 バケット命名規則に準拠）
    private var bucketNameGen: Gen<String> {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789-")
        return Gen<Character>.fromElements(of: chars)
            .proliferate(withSize: 12)
            .map { String($0) }
            .suchThat { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }
    }

    // MARK: - ヘルパー

    /// UUID パターンの正規表現（大文字ハイフン区切り形式）
    private let uuidPattern = "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"

    /// テスト用の AudioFile を作成するヘルパー
    private func makeAudioFile(fileName: String, ext: String) -> AudioFile {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).\(ext)")
        return AudioFile(
            id: UUID(),
            url: fileURL,
            fileName: fileName,
            fileExtension: ext,
            duration: 10.0,
            fileSize: 1024,
            createdAt: Date()
        )
    }

    // MARK: - プロパティテスト

    /// S3 キーが UUID パターンを含み、正しい拡張子を持ち、
    /// URI が s3://{bucket}/{key} 形式であり、複数回生成で一意であることを検証する
    func testS3KeyUniquenessAndUriFormat() {
        property("S3 キーの一意性と URI 形式: UUID を含み、正しい URI 形式で、複数回生成で一意")
            <- forAll(self.fileNameGen, self.extensionGen, self.bucketNameGen) {
                (fileName: String, ext: String, bucket: String) in

                let audioFile = self.makeAudioFile(fileName: fileName, ext: ext)

                // S3 キーを生成
                let key = AWSS3Service.generateS3Key(for: audioFile)

                // 1. キーが UUID パターンを含むことを検証
                let uuidRegex = try! NSRegularExpression(pattern: self.uuidPattern, options: [])
                let keyRange = NSRange(key.startIndex..., in: key)
                let containsUUID = uuidRegex.firstMatch(in: key, range: keyRange) != nil
                guard containsUUID else { return false }

                // 2. キーが正しい拡張子で終わることを検証
                guard key.hasSuffix(".\(ext)") else { return false }

                // 3. URI 形式が s3://{bucket}/{key} であることを検証
                let uri = AWSS3Service.buildS3Uri(bucket: bucket, key: key)
                let expectedUri = "s3://\(bucket)/\(key)"
                guard uri == expectedUri else { return false }

                // 4. URI が "s3://" プレフィックスで始まることを検証
                guard uri.hasPrefix("s3://") else { return false }

                // 5. 複数回生成で異なるキーが生成されることを検証（一意性）
                let key2 = AWSS3Service.generateS3Key(for: audioFile)
                guard key != key2 else { return false }

                return true
            }
    }
}
