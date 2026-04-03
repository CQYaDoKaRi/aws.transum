// TranscriberTests.swift
// Transcriber サービスのユニットテスト
// Transcribing プロトコルに準拠したモックを使用して、文字起こし機能を検証する
// 要件: 2.4, 2.5, 2.6, 2.7

import Testing
import Foundation
@testable import AudioTranscriptionSummary

// MARK: - MockTranscriber（テスト用モック）

/// Transcribing プロトコルに準拠したモック実装
/// 各テストシナリオ（正常系・無音・エラー・キャンセル）をシミュレートする
final class MockTranscriber: Transcribing, @unchecked Sendable {

    /// モックが返す結果を定義する列挙型
    enum MockResult {
        /// 正常な文字起こし結果を返す
        case success(String)
        /// 無音エラーを返す
        case silentAudio
        /// 文字起こし失敗エラーを返す
        case failure(Error)
    }

    /// モックが返す結果
    var mockResult: MockResult = .success("デフォルトテキスト")

    /// transcribe が呼ばれた回数
    private(set) var transcribeCallCount = 0

    /// cancel が呼ばれた回数
    private(set) var cancelCallCount = 0

    /// 最後に渡された言語
    private(set) var lastLanguage: TranscriptionLanguage?

    /// 進捗コールバックに送信する値のリスト
    var progressValues: [Double] = [0.3, 0.6, 1.0]

    /// キャンセル状態
    private var isCancelled = false

    func transcribe(
        audioFile: AudioFile,
        language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        transcribeCallCount += 1
        lastLanguage = language

        // 進捗コールバックを呼び出す
        for value in progressValues {
            onProgress(value)
        }

        // キャンセル済みの場合はエラーを返す
        if isCancelled {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "MockTranscriber", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "キャンセルされました"]
                )
            )
        }

        switch mockResult {
        case .success(let text):
            return Transcript(
                id: UUID(),
                audioFileId: audioFile.id,
                text: text,
                language: language,
                createdAt: Date()
            )
        case .silentAudio:
            throw AppError.silentAudio
        case .failure(let error):
            throw AppError.transcriptionFailed(underlying: error)
        }
    }

    func cancel() {
        cancelCallCount += 1
        isCancelled = true
    }

    /// キャンセル状態をリセットする（テスト間で再利用する場合）
    func reset() {
        isCancelled = false
        transcribeCallCount = 0
        cancelCallCount = 0
        lastLanguage = nil
    }
}

// MARK: - テスト用ヘルパー

/// テスト用の AudioFile を生成するヘルパー関数
private func makeTestAudioFile(
    fileName: String = "test_audio",
    fileExtension: String = "m4a",
    duration: TimeInterval = 60.0
) -> AudioFile {
    AudioFile(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/\(fileName).\(fileExtension)"),
        fileName: fileName,
        fileExtension: fileExtension,
        duration: duration,
        fileSize: 1024000,
        createdAt: Date()
    )
}


// MARK: - 日本語音声の文字起こしテスト（要件 2.4）

@Suite("Transcriber 日本語文字起こしテスト")
struct TranscriberJapaneseTests {

    /// 日本語音声の文字起こしが正常に完了し、Transcript が返されることを確認
    @Test func transcribeJapaneseAudio() async throws {
        let transcriber = MockTranscriber()
        let expectedText = "本日の会議では、新しいプロジェクトの進捗について議論しました。"
        transcriber.mockResult = .success(expectedText)

        let audioFile = makeTestAudioFile(fileName: "meeting_ja")
        var progressUpdates: [Double] = []

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { progress in progressUpdates.append(progress) }
        )

        // 文字起こし結果が正しいことを確認
        #expect(transcript.text == expectedText)
        // 言語が日本語であることを確認
        #expect(transcript.language == .japanese)
        // audioFileId が一致することを確認
        #expect(transcript.audioFileId == audioFile.id)
        // Transcript が空でないことを確認
        #expect(!transcript.isEmpty)
        // 渡された言語が日本語であることを確認
        #expect(transcriber.lastLanguage == .japanese)
    }

    /// 日本語の長文テキストが正しく文字起こしされることを確認
    @Test func transcribeJapaneseLongText() async throws {
        let transcriber = MockTranscriber()
        let longText = """
        音声認識技術は近年大きく進歩しています。\
        特に深層学習の発展により、認識精度が飛躍的に向上しました。\
        日本語のような複雑な言語体系を持つ言語でも、高い精度で文字起こしが可能になっています。
        """
        transcriber.mockResult = .success(longText)

        let audioFile = makeTestAudioFile(fileName: "lecture_ja", duration: 300.0)

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        #expect(transcript.text == longText)
        #expect(transcript.characterCount > 0)
        #expect(transcript.language == .japanese)
    }
}

// MARK: - 英語音声の文字起こしテスト（要件 2.5）

@Suite("Transcriber 英語文字起こしテスト")
struct TranscriberEnglishTests {

    /// 英語音声の文字起こしが正常に完了し、Transcript が返されることを確認
    @Test func transcribeEnglishAudio() async throws {
        let transcriber = MockTranscriber()
        let expectedText = "Today we discussed the progress of the new project in our meeting."
        transcriber.mockResult = .success(expectedText)

        let audioFile = makeTestAudioFile(fileName: "meeting_en")
        var progressUpdates: [Double] = []

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .english,
            onProgress: { progress in progressUpdates.append(progress) }
        )

        // 文字起こし結果が正しいことを確認
        #expect(transcript.text == expectedText)
        // 言語が英語であることを確認
        #expect(transcript.language == .english)
        // audioFileId が一致することを確認
        #expect(transcript.audioFileId == audioFile.id)
        // 渡された言語が英語であることを確認
        #expect(transcriber.lastLanguage == .english)
    }

    /// 英語の長文テキストが正しく文字起こしされることを確認
    @Test func transcribeEnglishLongText() async throws {
        let transcriber = MockTranscriber()
        let longText = """
        Speech recognition technology has made significant advances in recent years. \
        The development of deep learning has dramatically improved recognition accuracy. \
        Even complex languages can now be transcribed with high precision.
        """
        transcriber.mockResult = .success(longText)

        let audioFile = makeTestAudioFile(fileName: "lecture_en", duration: 300.0)

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .english,
            onProgress: { _ in }
        )

        #expect(transcript.text == longText)
        #expect(transcript.characterCount > 0)
        #expect(transcript.language == .english)
    }
}


// MARK: - 無音ファイルの検出テスト（要件 2.7）

@Suite("Transcriber 無音検出テスト")
struct TranscriberSilentAudioTests {

    /// 無音ファイルの場合に silentAudio エラーが発生することを確認
    @Test func detectSilentAudio() async {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .silentAudio

        let audioFile = makeTestAudioFile(fileName: "silent_audio")

        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
            Issue.record("silentAudio エラーが発生するべき")
        } catch let error as AppError {
            // silentAudio エラーであることを確認
            guard case .silentAudio = error else {
                Issue.record("silentAudio エラーが期待されたが、\(error) が発生")
                return
            }
            // エラーメッセージが正しいことを確認
            #expect(error.errorDescription == "音声が検出されませんでした")
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// 無音検出が英語モードでも正しく動作することを確認
    @Test func detectSilentAudioInEnglish() async {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .silentAudio

        let audioFile = makeTestAudioFile(fileName: "silent_audio_en")

        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile,
                language: .english,
                onProgress: { _ in }
            )
            Issue.record("silentAudio エラーが発生するべき")
        } catch let error as AppError {
            guard case .silentAudio = error else {
                Issue.record("silentAudio エラーが期待されたが、\(error) が発生")
                return
            }
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }
}

// MARK: - エラー発生時の再試行テスト（要件 2.6）

@Suite("Transcriber エラーと再試行テスト")
struct TranscriberErrorAndRetryTests {

    /// 文字起こし失敗時に transcriptionFailed エラーが発生することを確認
    @Test func transcriptionFailedError() async {
        let transcriber = MockTranscriber()
        let underlyingError = NSError(
            domain: "SpeechRecognition", code: -100,
            userInfo: [NSLocalizedDescriptionKey: "認識エンジンエラー"]
        )
        transcriber.mockResult = .failure(underlyingError)

        let audioFile = makeTestAudioFile(fileName: "error_audio")

        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
            Issue.record("transcriptionFailed エラーが発生するべき")
        } catch let error as AppError {
            guard case .transcriptionFailed(let underlying) = error else {
                Issue.record("transcriptionFailed エラーが期待されたが、\(error) が発生")
                return
            }
            // 元のエラーが保持されていることを確認
            let nsError = underlying as NSError
            #expect(nsError.code == -100)
            // エラーメッセージに「文字起こしに失敗しました」が含まれることを確認
            #expect(error.errorDescription?.contains("文字起こしに失敗しました") == true)
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// エラー後に再試行（同じパラメータで再実行）が成功することを確認
    @Test func retryAfterFailure() async throws {
        let transcriber = MockTranscriber()
        let audioFile = makeTestAudioFile(fileName: "retry_audio")

        // 1回目: エラーを発生させる
        let underlyingError = NSError(
            domain: "SpeechRecognition", code: -200,
            userInfo: [NSLocalizedDescriptionKey: "一時的なエラー"]
        )
        transcriber.mockResult = .failure(underlyingError)

        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
            Issue.record("1回目は transcriptionFailed エラーが発生するべき")
        } catch is AppError {
            // 期待通りエラーが発生
        }

        #expect(transcriber.transcribeCallCount == 1)

        // 2回目: 成功するように設定して再試行
        let expectedText = "再試行で成功した文字起こし結果です。"
        transcriber.mockResult = .success(expectedText)

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        // 再試行が成功したことを確認
        #expect(transcript.text == expectedText)
        #expect(transcript.audioFileId == audioFile.id)
        // transcribe が合計2回呼ばれたことを確認
        #expect(transcriber.transcribeCallCount == 2)
    }

    /// 複数回連続でエラーが発生しても、最終的に成功できることを確認
    @Test func retryMultipleFailures() async throws {
        let transcriber = MockTranscriber()
        let audioFile = makeTestAudioFile(fileName: "multi_retry_audio")

        // 1回目: エラー
        transcriber.mockResult = .failure(
            NSError(domain: "Test", code: -1, userInfo: nil)
        )
        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile, language: .english, onProgress: { _ in }
            )
        } catch {}

        // 2回目: エラー
        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile, language: .english, onProgress: { _ in }
            )
        } catch {}

        #expect(transcriber.transcribeCallCount == 2)

        // 3回目: 成功
        let expectedText = "Third time is the charm."
        transcriber.mockResult = .success(expectedText)

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile, language: .english, onProgress: { _ in }
        )

        #expect(transcript.text == expectedText)
        #expect(transcriber.transcribeCallCount == 3)
    }
}


// MARK: - 進捗コールバックテスト

@Suite("Transcriber 進捗コールバックテスト")
struct TranscriberProgressTests {

    /// 進捗コールバックが正しく呼び出されることを確認
    @Test func progressCallbackInvoked() async throws {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("テスト")
        transcriber.progressValues = [0.1, 0.3, 0.5, 0.8, 1.0]

        let audioFile = makeTestAudioFile()
        var receivedProgress: [Double] = []

        _ = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { progress in receivedProgress.append(progress) }
        )

        // 進捗値がすべて受信されたことを確認
        #expect(receivedProgress == [0.1, 0.3, 0.5, 0.8, 1.0])
    }

    /// 進捗値が 0.0〜1.0 の範囲内であることを確認
    @Test func progressValuesInRange() async throws {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("テスト")
        transcriber.progressValues = [0.0, 0.25, 0.5, 0.75, 1.0]

        let audioFile = makeTestAudioFile()
        var receivedProgress: [Double] = []

        _ = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { progress in receivedProgress.append(progress) }
        )

        // すべての進捗値が 0.0〜1.0 の範囲内であることを確認
        for value in receivedProgress {
            #expect(value >= 0.0 && value <= 1.0, "進捗値 \(value) が範囲外")
        }
    }
}

// MARK: - キャンセル機能テスト

@Suite("Transcriber キャンセルテスト")
struct TranscriberCancelTests {

    /// cancel() が呼び出されたことを確認
    @Test func cancelInvoked() {
        let transcriber = MockTranscriber()

        transcriber.cancel()

        #expect(transcriber.cancelCallCount == 1)
    }

    /// cancel() 後の transcribe がエラーを返すことを確認
    @Test func transcribeAfterCancel() async {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("テスト")

        // キャンセルを実行
        transcriber.cancel()

        let audioFile = makeTestAudioFile()

        do {
            _ = try await transcriber.transcribe(
                audioFile: audioFile,
                language: .japanese,
                onProgress: { _ in }
            )
            Issue.record("キャンセル後は transcriptionFailed エラーが発生するべき")
        } catch let error as AppError {
            guard case .transcriptionFailed = error else {
                Issue.record("transcriptionFailed エラーが期待されたが、\(error) が発生")
                return
            }
            // 正常: キャンセルによるエラーが発生
        } catch {
            Issue.record("AppError が期待されたが、\(error) が発生")
        }
    }

    /// cancel() 複数回呼び出しが安全であることを確認
    @Test func multipleCancels() {
        let transcriber = MockTranscriber()

        transcriber.cancel()
        transcriber.cancel()
        transcriber.cancel()

        #expect(transcriber.cancelCallCount == 3)
    }
}

// MARK: - Transcript モデル生成テスト

@Suite("Transcriber Transcript 生成テスト")
struct TranscriberTranscriptGenerationTests {

    /// 生成された Transcript の audioFileId が元の AudioFile の id と一致することを確認
    @Test func transcriptAudioFileIdMatches() async throws {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("テスト文字列")

        let audioFile = makeTestAudioFile()

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        #expect(transcript.audioFileId == audioFile.id)
    }

    /// 生成された Transcript の言語が指定した言語と一致することを確認
    @Test func transcriptLanguageMatches() async throws {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("Test text")

        let audioFile = makeTestAudioFile()

        // 英語で文字起こし
        let englishTranscript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .english,
            onProgress: { _ in }
        )
        #expect(englishTranscript.language == .english)

        // 日本語で文字起こし
        transcriber.mockResult = .success("テスト文字列")
        let japaneseTranscript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )
        #expect(japaneseTranscript.language == .japanese)
    }

    /// 生成された Transcript の createdAt が現在時刻に近いことを確認
    @Test func transcriptCreatedAtIsRecent() async throws {
        let transcriber = MockTranscriber()
        transcriber.mockResult = .success("テスト")

        let audioFile = makeTestAudioFile()
        let beforeTime = Date()

        let transcript = try await transcriber.transcribe(
            audioFile: audioFile,
            language: .japanese,
            onProgress: { _ in }
        )

        let afterTime = Date()

        // createdAt が実行前後の時刻の間にあることを確認
        #expect(transcript.createdAt >= beforeTime)
        #expect(transcript.createdAt <= afterTime)
    }
}
