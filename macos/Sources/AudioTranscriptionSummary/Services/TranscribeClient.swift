// TranscribeClient.swift
// Amazon Transcribe を使用した文字起こしクライアント
// 認証情報の検証 → S3 アップロード → ジョブ作成 → ポーリング → 結果取得 → クリーンアップの処理フローを実装

import Foundation

// MARK: - TranscribeClient（Amazon Transcribe 文字起こしクライアント）

/// Amazon Transcribe を使用した文字起こしサービス
/// 既存の `Transcribing` プロトコルに準拠し、AppViewModel への DI で切り替え可能
final class TranscribeClient: Transcribing, @unchecked Sendable {

    // MARK: - プロパティ

    /// AWS 認証情報マネージャー
    private let credentialManager: any AWSCredentialManaging
    /// S3 バケット名
    private let s3BucketName: String
    /// S3 クライアント（プロトコルベース DI）
    private let s3Client: any S3ClientProtocol
    /// Transcribe クライアント（プロトコルベース DI）
    private let transcribeClient: any TranscribeClientProtocol

    /// キャンセル状態フラグ
    private var isCancelled = false
    /// スレッドセーフなアクセス用ロック
    private let lock = NSLock()

    /// ポーリング間隔（秒）
    private let pollingInterval: UInt64

    // MARK: - 初期化

    /// TranscribeClient を初期化する
    /// - Parameters:
    ///   - credentialManager: AWS 認証情報マネージャー
    ///   - s3BucketName: 音声ファイルアップロード先の S3 バケット名
    ///   - s3Client: S3 操作クライアント
    ///   - transcribeClient: Transcribe 操作クライアント
    ///   - pollingInterval: ポーリング間隔（ナノ秒）。デフォルトは 3 秒
    init(
        credentialManager: any AWSCredentialManaging,
        s3BucketName: String,
        s3Client: any S3ClientProtocol,
        transcribeClient: any TranscribeClientProtocol,
        pollingInterval: UInt64 = 3_000_000_000
    ) {
        self.credentialManager = credentialManager
        self.s3BucketName = s3BucketName
        self.s3Client = s3Client
        self.transcribeClient = transcribeClient
        self.pollingInterval = pollingInterval
    }

    // MARK: - Transcribing プロトコル準拠

    /// 音声ファイルの文字起こしを実行する
    ///
    /// 処理フロー:
    /// 1. 認証情報の検証
    /// 2. S3 へ音声ファイルをアップロード
    /// 3. Transcribe ジョブの作成
    /// 4. ポーリングによるジョブステータス確認
    /// 5. 結果テキストの取得と無音チェック
    /// 6. S3 一時ファイルのクリーンアップ
    ///
    /// - Parameters:
    ///   - audioFile: 文字起こし対象の音声ファイル
    ///   - language: 文字起こしに使用する言語
    ///   - onProgress: 進捗コールバック（0.0〜1.0）
    /// - Returns: 生成された Transcript
    /// - Throws: `AppError.transcriptionFailed` または `AppError.silentAudio`
    func transcribe(
        audioFile: AudioFile,
        language: TranscriptionLanguage,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> Transcript {
        // キャンセル状態をリセット
        resetCancelled()

        var s3Key: String?

        do {
            // 1. 認証情報の検証
            _ = try validateCredentials()
            onProgress(0.1)

            // キャンセルチェック
            try checkCancelled()

            // 2. S3 へ音声ファイルをアップロード
            let key = AWSS3Service.generateS3Key(for: audioFile)
            s3Key = key
            try await s3Client.putObject(bucket: s3BucketName, key: key, fileURL: audioFile.url)
            onProgress(0.2)

            // キャンセルチェック
            try checkCancelled()

            // 3. Transcribe ジョブの作成
            let s3Uri = AWSS3Service.buildS3Uri(bucket: s3BucketName, key: key)
            let jobConfig = TranscribeJobConfig(
                jobName: "transcribe-\(UUID().uuidString)",
                mediaFileUri: s3Uri,
                languageCode: language.rawValue,
                outputBucketName: nil
            )
            let jobName = try await transcribeClient.startTranscriptionJob(config: jobConfig)
            onProgress(0.4)

            // 4. ポーリングによるジョブステータス確認
            let transcriptText = try await pollJobStatus(jobName: jobName, onProgress: onProgress)

            // 5. 無音チェック
            if transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // クリーンアップ後に silentAudio を投げる
                await cleanupS3File(key: key)
                onProgress(1.0)
                throw AppError.silentAudio
            }
            onProgress(0.9)

            // 6. S3 一時ファイルのクリーンアップ（ベストエフォート）
            await cleanupS3File(key: key)
            onProgress(1.0)

            // Transcript モデルを返却
            return Transcript(
                id: UUID(),
                audioFileId: audioFile.id,
                text: transcriptText,
                language: language,
                createdAt: Date()
            )
        } catch {
            // エラー時も S3 一時ファイルの削除を試みる（ベストエフォート）
            if let key = s3Key {
                await cleanupS3File(key: key)
            }
            // AppError はそのまま再スロー、それ以外は mapAWSError で変換
            if error is AppError {
                throw error
            }
            throw mapAWSError(error)
        }
    }

    /// 文字起こし処理をキャンセルする
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    // MARK: - プライベートメソッド

    /// 認証情報を検証する
    /// - Returns: 有効な AWSCredentials
    /// - Throws: 認証情報が未設定または無効の場合
    private func validateCredentials() throws -> AWSCredentials {
        guard let credentials = credentialManager.loadCredentials() else {
            throw AppError.transcriptionFailed(underlying: NSError(
                domain: "TranscribeClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AWS 認証情報が設定されていません。設定画面から認証情報を入力してください"]
            ))
        }

        guard credentials.isValid else {
            throw AppError.transcriptionFailed(underlying: NSError(
                domain: "TranscribeClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "AWS 認証情報が無効です。設定画面で認証情報を確認してください"]
            ))
        }

        return credentials
    }

    /// ポーリングでジョブステータスを確認する
    /// 3 秒間隔で getTranscriptionJob を呼び出し、完了または失敗まで繰り返す
    /// - Parameters:
    ///   - jobName: 確認するジョブ名
    ///   - onProgress: 進捗コールバック（0.4〜0.8 の範囲で通知）
    /// - Returns: 文字起こし結果テキスト
    /// - Throws: ジョブ失敗またはキャンセル時
    private func pollJobStatus(
        jobName: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        var pollCount = 0
        let maxPollsForProgress = 10 // 進捗計算用の最大ポーリング回数

        while true {
            // キャンセルチェック
            try checkCancelled()

            let status = try await transcribeClient.getTranscriptionJob(jobName: jobName)

            switch status {
            case .completed(let transcriptText):
                return transcriptText

            case .failed(let reason):
                throw AppError.transcriptionFailed(underlying: NSError(
                    domain: "TranscribeClient",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "文字起こしジョブが失敗しました: \(reason)"]
                ))

            case .inProgress:
                pollCount += 1
                // 進捗を 0.4〜0.8 の範囲で通知
                let progressFraction = min(Double(pollCount) / Double(maxPollsForProgress), 1.0)
                let progress = 0.4 + (0.4 * progressFraction)
                onProgress(min(progress, 0.8))

                // ポーリング間隔待機
                try await Task.sleep(nanoseconds: pollingInterval)
            }
        }
    }

    /// S3 一時ファイルを削除する（ベストエフォート）
    /// 削除失敗はログに記録するが、エラーとしては伝播しない
    /// - Parameter key: 削除する S3 オブジェクトキー
    private func cleanupS3File(key: String) async {
        do {
            try await s3Client.deleteObject(bucket: s3BucketName, key: key)
        } catch {
            // ベストエフォート: 削除失敗は無視する
            // 本番環境ではログに記録することを推奨
        }
    }

    /// キャンセル状態を確認し、キャンセルされていれば例外をスローする
    /// - Throws: キャンセル時に CancellationError
    private func checkCancelled() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()

        if cancelled {
            throw CancellationError()
        }
    }

    /// キャンセル状態をリセットする
    private func resetCancelled() {
        lock.lock()
        isCancelled = false
        lock.unlock()
    }

    /// AWS SDK エラーを AppError に変換する
    /// - Parameter error: 変換元のエラー
    /// - Returns: 適切な AppError
    private func mapAWSError(_ error: Error) -> AppError {
        // CancellationError の場合
        if error is CancellationError {
            return .transcriptionFailed(underlying: NSError(
                domain: "TranscribeClient",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "文字起こしがキャンセルされました"]
            ))
        }

        let nsError = error as NSError

        // ネットワークエラーの判定
        if nsError.domain == NSURLErrorDomain {
            return .transcriptionFailed(underlying: NSError(
                domain: "TranscribeClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "ネットワーク接続を確認してください"]
            ))
        }

        // S3 アクセス拒否の判定
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("access denied") || errorDescription.contains("forbidden") {
            return .transcriptionFailed(underlying: NSError(
                domain: "TranscribeClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "S3 バケットへのアクセス権限がありません。IAM ポリシーを確認してください"]
            ))
        }

        // その他のエラー
        return .transcriptionFailed(underlying: error)
    }
}
