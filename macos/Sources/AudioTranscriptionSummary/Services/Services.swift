// Services.swift
// サービス層のプロトコル定義
// 各サービスのインターフェースを定義し、実装の詳細を分離する

import Foundation

// MARK: - FileImporting（ファイル読み込みプロトコル）

/// 音声ファイルの読み込みとバリデーションを担当するプロトコル
protocol FileImporting {
    /// サポートされる音声ファイル形式の拡張子一覧
    static var supportedExtensions: Set<String> { get }

    /// 音声ファイルを読み込み、AudioFile モデルを返す
    /// - Parameter url: 読み込む音声ファイルの URL
    /// - Returns: 読み込まれた AudioFile
    /// - Throws: `AppError.unsupportedFormat` または `AppError.corruptedFile`
    func importFile(from url: URL) async throws -> AudioFile

    /// ファイル形式がサポート対象かを判定する
    /// - Parameter fileExtension: 判定するファイル拡張子
    /// - Returns: サポート対象であれば true
    func isSupported(fileExtension: String) -> Bool
}

// MARK: - Transcribing（文字起こしプロトコル）

/// 音声認識による文字起こしを担当するプロトコル
protocol Transcribing {
    /// 音声ファイルの文字起こしを実行する
    /// - Parameters:
    ///   - audioFile: 文字起こし対象の音声ファイル
    ///   - language: 文字起こしに使用する言語
    ///   - onProgress: 進捗コールバック（0.0〜1.0）
    /// - Returns: 生成された Transcript
    /// - Throws: `AppError.transcriptionFailed` または `AppError.silentAudio`
    func transcribe(audioFile: AudioFile, language: TranscriptionLanguage,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws -> Transcript

    /// 文字起こし処理をキャンセルする
    func cancel()
}

// MARK: - Summarizing（要約プロトコル）

/// 文字起こしテキストの要約を担当するプロトコル
protocol Summarizing {
    /// Transcript の要約を生成する
    /// - Parameter transcript: 要約対象の Transcript
    /// - Returns: 生成された Summary
    /// - Throws: `AppError.summarizationFailed` または `AppError.insufficientContent`
    func summarize(transcript: Transcript) async throws -> Summary

    /// 要約可能な最小文字数
    static var minimumCharacterCount: Int { get }
}

// MARK: - AudioPlaying（音声再生プロトコル）

/// 音声ファイルの再生を担当するプロトコル
protocol AudioPlaying {
    /// 再生中かどうか
    var isPlaying: Bool { get }
    /// 現在の再生位置（秒）
    var currentTime: TimeInterval { get }
    /// 音声の総再生時間（秒）
    var duration: TimeInterval { get }

    /// 音声ファイルを読み込む
    /// - Parameter audioFile: 読み込む音声ファイル
    /// - Throws: 読み込みに失敗した場合
    func load(audioFile: AudioFile) throws

    /// 再生を開始する
    func play()

    /// 再生を一時停止する
    func pause()

    /// 指定位置にシークする
    /// - Parameter time: シーク先の位置（秒）
    func seek(to time: TimeInterval)
}

// MARK: - Exporting（エクスポートプロトコル）

/// 文字起こし結果と要約のエクスポートを担当するプロトコル
protocol Exporting {
    /// Transcript と Summary をテキストファイルとして保存する
    /// - Parameters:
    ///   - transcript: エクスポートする Transcript
    ///   - summary: エクスポートする Summary（省略可）
    ///   - directory: 保存先ディレクトリの URL
    /// - Returns: 保存されたファイルの URL
    /// - Throws: `AppError.exportFailed` または `AppError.writePermissionDenied`
    func export(transcript: Transcript, summary: Summary?, to directory: URL) async throws -> URL

    /// 指定ディレクトリへの書き込み権限を確認する
    /// - Parameter directory: 確認するディレクトリの URL
    /// - Returns: 書き込み可能であれば true
    func canWrite(to directory: URL) -> Bool
}

// MARK: - S3ClientProtocol（S3 クライアントプロトコル）

/// Amazon S3 のファイル操作を抽象化するプロトコル
/// テスト時にモック実装を注入するために使用する
protocol S3ClientProtocol: Sendable {
    /// S3 バケットにファイルをアップロードする
    /// - Parameters:
    ///   - bucket: アップロード先の S3 バケット名
    ///   - key: S3 オブジェクトキー
    ///   - fileURL: アップロードするローカルファイルの URL
    /// - Throws: アップロードに失敗した場合
    func putObject(bucket: String, key: String, fileURL: URL) async throws

    /// S3 バケットからオブジェクトを削除する
    /// - Parameters:
    ///   - bucket: 削除対象の S3 バケット名
    ///   - key: 削除する S3 オブジェクトキー
    /// - Throws: 削除に失敗した場合
    func deleteObject(bucket: String, key: String) async throws
}

// MARK: - TranscribeClientProtocol（Transcribe クライアントプロトコル）

/// Amazon Transcribe のジョブ操作を抽象化するプロトコル
/// テスト時にモック実装を注入するために使用する
protocol TranscribeClientProtocol: Sendable {
    /// 文字起こしジョブを開始する
    /// - Parameter config: ジョブの設定
    /// - Returns: 作成されたジョブ名
    /// - Throws: ジョブ作成に失敗した場合
    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String

    /// 文字起こしジョブのステータスを取得する
    /// - Parameter jobName: 確認するジョブ名
    /// - Returns: ジョブの現在のステータス
    /// - Throws: ステータス取得に失敗した場合
    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus
}

// MARK: - TranscriptionJobStatus（ジョブステータス）

/// Amazon Transcribe ジョブのステータスを表す列挙型
enum TranscriptionJobStatus: Sendable {
    /// ジョブが実行中
    case inProgress
    /// ジョブが完了し、文字起こしテキストが取得可能
    case completed(transcriptText: String)
    /// ジョブが失敗し、失敗理由が取得可能
    case failed(reason: String)
}

// MARK: - AWSCredentialManaging（AWS 認証情報管理プロトコル）

/// AWS 認証情報の保存・読み込み・削除を担当するプロトコル
/// macOS Keychain を使用した安全な認証情報管理を抽象化する
protocol AWSCredentialManaging: Sendable {
    /// Keychain から認証情報を読み込む
    /// - Returns: 保存済みの認証情報。未設定の場合は nil
    func loadCredentials() -> AWSCredentials?

    /// 認証情報を Keychain に保存する
    /// - Parameter credentials: 保存する認証情報
    /// - Throws: Keychain 操作に失敗した場合
    func saveCredentials(_ credentials: AWSCredentials) throws

    /// Keychain から認証情報を削除する
    /// - Throws: Keychain 操作に失敗した場合
    func deleteCredentials() throws

    /// 認証情報が設定済みかどうか
    var hasCredentials: Bool { get }
}
