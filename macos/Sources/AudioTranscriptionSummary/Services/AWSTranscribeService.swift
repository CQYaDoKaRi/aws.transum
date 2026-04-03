// AWSTranscribeService.swift
// Amazon Transcribe SDK をラップした TranscribeClientProtocol の具象実装
// ジョブの作成・ステータス取得・結果テキスト抽出を担当する

import Foundation
import AWSTranscribe
import SmithyIdentity

// MARK: - AWSTranscribeService（Transcribe クライアント実装）

/// Amazon Transcribe SDK を使用したジョブ操作の実装
/// TranscribeClientProtocol に準拠し、DI によるテスタビリティを確保する
final class AWSTranscribeService: TranscribeClientProtocol, Sendable {

    // MARK: - プロパティ

    /// AWS SDK の Transcribe クライアント
    /// 自作の TranscribeClient との名前衝突を避けるためモジュール修飾名を使用
    private let client: AWSTranscribe.TranscribeClient

    // MARK: - 初期化

    /// AWSCredentials を使用して Transcribe クライアントを初期化する
    /// - Parameter credentials: AWS 認証情報
    /// - Throws: クライアントの初期化に失敗した場合
    init(credentials: AWSCredentials) throws {
        let identity = AWSCredentialIdentity(
            accessKey: credentials.accessKeyId,
            secret: credentials.secretAccessKey
        )
        let resolver = StaticAWSCredentialIdentityResolver(identity)
        let config = try AWSTranscribe.TranscribeClient.TranscribeClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: credentials.region
        )
        self.client = AWSTranscribe.TranscribeClient(config: config)
    }

    // MARK: - TranscribeClientProtocol 準拠

    /// 文字起こしジョブを開始する
    /// - Parameter config: ジョブの設定（ジョブ名、メディア URI、言語コード）
    /// - Returns: 作成されたジョブ名
    /// - Throws: ジョブ作成に失敗した場合
    func startTranscriptionJob(config: TranscribeJobConfig) async throws -> String {
        var input = StartTranscriptionJobInput(
            media: TranscribeClientTypes.Media(mediaFileUri: config.mediaFileUri),
            outputBucketName: config.outputBucketName,
            transcriptionJobName: config.jobName
        )
        // 言語設定: auto の場合は自動判別、それ以外は指定言語
        if config.languageCode == "auto" {
            input.identifyLanguage = true
            input.languageOptions = [.jaJp, .enUs]
        } else {
            input.languageCode = TranscribeClientTypes.LanguageCode(rawValue: config.languageCode)
        }
        let output = try await client.startTranscriptionJob(input: input)
        return output.transcriptionJob?.transcriptionJobName ?? config.jobName
    }

    /// 文字起こしジョブのステータスを取得する
    /// ジョブが完了した場合、結果 URI からテキストを取得して返す
    /// - Parameter jobName: 確認するジョブ名
    /// - Returns: ジョブの現在のステータス
    /// - Throws: ステータス取得に失敗した場合
    func getTranscriptionJob(jobName: String) async throws -> TranscriptionJobStatus {
        let input = GetTranscriptionJobInput(transcriptionJobName: jobName)
        let output = try await client.getTranscriptionJob(input: input)

        guard let job = output.transcriptionJob else {
            return .failed(reason: "ジョブ情報を取得できませんでした")
        }

        switch job.transcriptionJobStatus {
        case .completed:
            // 結果 URI からテキストを取得
            if let uri = job.transcript?.transcriptFileUri,
               let url = URL(string: uri) {
                let text = try await fetchTranscriptText(from: url)
                return .completed(transcriptText: text)
            }
            return .failed(reason: "文字起こし結果の URI が取得できませんでした")

        case .failed:
            let reason = job.failureReason ?? "不明なエラー"
            return .failed(reason: reason)

        case .inProgress, .queued:
            return .inProgress

        default:
            return .inProgress
        }
    }

    // MARK: - プライベートメソッド

    /// Transcribe の結果 JSON からテキストを抽出する
    /// - Parameter url: 結果 JSON の URL
    /// - Returns: 抽出された文字起こしテキスト
    /// - Throws: テキスト取得に失敗した場合
    private func fetchTranscriptText(from url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)

        // Amazon Transcribe の結果 JSON 構造:
        // { "results": { "transcripts": [{ "transcript": "テキスト" }] } }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let transcripts = results["transcripts"] as? [[String: Any]],
              let firstTranscript = transcripts.first,
              let text = firstTranscript["transcript"] as? String else {
            throw NSError(
                domain: "AWSTranscribeService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "文字起こし結果の解析に失敗しました"]
            )
        }

        return text
    }
}
