// Transcriber.swift
// 音声認識による文字起こしを担当するサービス
// SFSpeechRecognizer を用いて音声ファイルをテキストに変換する

import Foundation
import Speech

// MARK: - Transcriber（文字起こしサービス）

/// Transcribing プロトコルに準拠した音声認識サービス
/// Apple の Speech フレームワーク（SFSpeechRecognizer）を使用して
/// 日本語・英語の音声ファイルを文字起こしする
final class Transcriber: Transcribing, @unchecked Sendable {

    // MARK: - プロパティ

    /// 現在実行中の認識タスク（キャンセル用に保持）
    private var currentTask: SFSpeechRecognitionTask?

    /// キャンセル状態を管理するロック
    private let lock = NSLock()

    // MARK: - 文字起こし

    /// 音声ファイルの文字起こしを実行する
    ///
    /// 処理フロー:
    /// 1. SFSpeechRecognizer の初期化（指定言語）
    /// 2. SFSpeechURLRecognitionRequest の作成
    /// 3. 認識タスクの開始と進捗コールバック
    /// 4. 認識結果の Transcript モデルへの変換
    /// 5. 無音検出時の専用メッセージ返却
    ///
    /// - Parameters:
    ///   - audioFile: 文字起こし対象の音声ファイル
    ///   - language: 文字起こしに使用する言語（日本語 or 英語）
    ///   - onProgress: 進捗コールバック（0.0〜1.0）
    /// - Returns: 生成された Transcript
    /// - Throws: `AppError.transcriptionFailed` または `AppError.silentAudio`
    func transcribe(
        audioFile: AudioFile,
        language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        // 1. SFSpeechRecognizer の初期化（指定言語のロケールを使用）
        let locale = Locale(identifier: language.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "Transcriber",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "音声認識エンジンの初期化に失敗しました"]
                )
            )
        }

        // 音声認識が利用可能か確認
        guard recognizer.isAvailable else {
            throw AppError.transcriptionFailed(
                underlying: NSError(
                    domain: "Transcriber",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "音声認識が現在利用できません"]
                )
            )
        }

        // 2. SFSpeechURLRecognitionRequest の作成
        let request = SFSpeechURLRecognitionRequest(url: audioFile.url)
        request.shouldReportPartialResults = true

        // 3. 認識タスクの開始（withCheckedThrowingContinuation で async/await に変換）
        let transcribedText: String = try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let resumeLock = NSLock()

            /// continuation を安全に一度だけ resume するヘルパー
            func safeResume(with result: Result<String, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let task = recognizer.recognitionTask(with: request) { result, error in
                // エラーが発生した場合
                if let error = error {
                    // キャンセルによるエラーの場合
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // 無音検出
                        safeResume(with: .failure(AppError.silentAudio))
                        return
                    }
                    if nsError.code == 1 || nsError.code == 301 {
                        // キャンセルまたは中断
                        safeResume(with: .failure(
                            AppError.transcriptionFailed(underlying: error)
                        ))
                        return
                    }
                }

                if let result = result {
                    if result.isFinal {
                        // 認識完了: 最終結果を返す
                        let text = result.bestTranscription.formattedString
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // 認識結果が空の場合は無音とみなす
                            safeResume(with: .failure(AppError.silentAudio))
                        } else {
                            // 進捗を 1.0（完了）に設定
                            onProgress(1.0)
                            safeResume(with: .success(text))
                        }
                    } else {
                        // 部分結果: 進捗を推定して通知
                        // isFinal でない間は 0.1〜0.9 の範囲で進捗を推定
                        let partialText = result.bestTranscription.formattedString
                        let estimatedProgress = min(0.9, Double(partialText.count) / max(1.0, Double(partialText.count + 50)))
                        onProgress(max(0.1, estimatedProgress))
                    }
                } else if let error = error {
                    // 結果なし + エラーあり: 文字起こし失敗
                    safeResume(with: .failure(
                        AppError.transcriptionFailed(underlying: error)
                    ))
                }
            }

            // 認識タスクを保持（キャンセル用）
            self.lock.lock()
            self.currentTask = task
            self.lock.unlock()
        }

        // タスク完了後にクリア
        clearCurrentTask()

        // 4. 認識結果の Transcript モデルへの変換
        return Transcript(
            id: UUID(),
            audioFileId: audioFile.id,
            text: transcribedText,
            language: language,
            createdAt: Date()
        )
    }

    // MARK: - 内部ヘルパー

    /// 現在のタスクをスレッドセーフにクリアする（非 async コンテキストから呼び出し可能）
    private nonisolated func clearCurrentTask() {
        lock.lock()
        currentTask = nil
        lock.unlock()
    }

    // MARK: - キャンセル

    /// 文字起こし処理をキャンセルする
    /// 現在実行中の SFSpeechRecognitionTask の cancel() を呼び出す
    func cancel() {
        lock.lock()
        let task = currentTask
        currentTask = nil
        lock.unlock()
        task?.cancel()
    }
}
