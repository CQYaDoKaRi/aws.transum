// ModelsTests.swift
// データモデル（AudioFile, Transcript, Summary, TranscriptionLanguage）のユニットテスト

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - TranscriptionLanguage テスト

@Suite("TranscriptionLanguage テスト")
struct TranscriptionLanguageTests {

    /// 日本語の rawValue が "ja-JP" であることを確認
    @Test func japaneseRawValue() {
        #expect(TranscriptionLanguage.japanese.rawValue == "ja-JP")
    }

    /// 英語の rawValue が "en-US" であることを確認
    @Test func englishRawValue() {
        #expect(TranscriptionLanguage.english.rawValue == "en-US")
    }

    /// rawValue から TranscriptionLanguage を生成できることを確認
    @Test func initFromRawValue() {
        #expect(TranscriptionLanguage(rawValue: "ja-JP") == .japanese)
        #expect(TranscriptionLanguage(rawValue: "en-US") == .english)
        #expect(TranscriptionLanguage(rawValue: "fr-FR") == nil)
    }
}

// MARK: - AudioFile テスト

@Suite("AudioFile テスト")
struct AudioFileTests {

    /// AudioFile の全プロパティが正しく保持されることを確認
    @Test func properties() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let date = Date()

        let audioFile = AudioFile(
            id: id, url: url, fileName: "test", fileExtension: "m4a",
            duration: 120.5, fileSize: 1024000, createdAt: date
        )

        #expect(audioFile.id == id)
        #expect(audioFile.url == url)
        #expect(audioFile.fileName == "test")
        #expect(audioFile.fileExtension == "m4a")
        #expect(audioFile.duration == 120.5)
        #expect(audioFile.fileSize == 1024000)
        #expect(audioFile.createdAt == date)
    }

    /// AudioFile の Equatable 準拠を確認
    @Test func equatable() {
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        let date = Date()

        let a = AudioFile(id: id, url: url, fileName: "test", fileExtension: "m4a",
                          duration: 60.0, fileSize: 512, createdAt: date)
        let b = AudioFile(id: id, url: url, fileName: "test", fileExtension: "m4a",
                          duration: 60.0, fileSize: 512, createdAt: date)

        #expect(a == b)
    }
}

// MARK: - Transcript テスト

@Suite("Transcript テスト")
struct TranscriptTests {

    /// Transcript の全プロパティが正しく保持されることを確認
    @Test func properties() {
        let id = UUID()
        let audioFileId = UUID()
        let date = Date()

        let transcript = Transcript(
            id: id, audioFileId: audioFileId,
            text: "こんにちは世界", language: .japanese, createdAt: date
        )

        #expect(transcript.id == id)
        #expect(transcript.audioFileId == audioFileId)
        #expect(transcript.text == "こんにちは世界")
        #expect(transcript.language == .japanese)
        #expect(transcript.createdAt == date)
    }

    /// isEmpty が通常テキストで false を返すことを確認
    @Test func isEmptyWithContent() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "テスト文字列", language: .japanese, createdAt: Date()
        )
        #expect(transcript.isEmpty == false)
    }

    /// isEmpty が空文字列で true を返すことを確認
    @Test func isEmptyWithEmptyString() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "", language: .japanese, createdAt: Date()
        )
        #expect(transcript.isEmpty == true)
    }

    /// isEmpty が空白・改行のみで true を返すことを確認
    @Test func isEmptyWithWhitespace() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "   \n\t  ", language: .japanese, createdAt: Date()
        )
        #expect(transcript.isEmpty == true)
    }

    /// characterCount が正しい文字数を返すことを確認
    @Test func characterCount() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "Hello", language: .english, createdAt: Date()
        )
        #expect(transcript.characterCount == 5)
    }

    /// characterCount が日本語テキストで正しい文字数を返すことを確認
    @Test func characterCountJapanese() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "こんにちは", language: .japanese, createdAt: Date()
        )
        #expect(transcript.characterCount == 5)
    }

    /// characterCount が空文字列で 0 を返すことを確認
    @Test func characterCountEmpty() {
        let transcript = Transcript(
            id: UUID(), audioFileId: UUID(),
            text: "", language: .japanese, createdAt: Date()
        )
        #expect(transcript.characterCount == 0)
    }
}

// MARK: - Summary テスト

@Suite("Summary テスト")
struct SummaryTests {

    /// Summary の全プロパティが正しく保持されることを確認
    @Test func properties() {
        let id = UUID()
        let transcriptId = UUID()
        let date = Date()

        let summary = Summary(
            id: id, transcriptId: transcriptId,
            text: "要約テキスト", createdAt: date
        )

        #expect(summary.id == id)
        #expect(summary.transcriptId == transcriptId)
        #expect(summary.text == "要約テキスト")
        #expect(summary.createdAt == date)
    }

    /// Summary の Equatable 準拠を確認
    @Test func equatable() {
        let id = UUID()
        let transcriptId = UUID()
        let date = Date()

        let a = Summary(id: id, transcriptId: transcriptId, text: "要約", createdAt: date)
        let b = Summary(id: id, transcriptId: transcriptId, text: "要約", createdAt: date)

        #expect(a == b)
    }
}
