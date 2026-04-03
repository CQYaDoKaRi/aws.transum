// TranscribeJobConfig.swift
// Amazon Transcribe ジョブの設定データモデル定義

import Foundation

// MARK: - TranscribeJobConfig（Transcribe ジョブ設定）

/// Amazon Transcribe ジョブの設定を保持する構造体
/// ジョブ作成時に必要なパラメータをまとめて管理する
struct TranscribeJobConfig: Equatable, Sendable {
    /// ジョブ名（UUID ベース）
    let jobName: String
    /// S3 上の音声ファイル URI（例: "s3://bucket/uuid.m4a"）
    let mediaFileUri: String
    /// 言語コード（例: "ja-JP", "en-US"）
    let languageCode: String
    /// 出力先 S3 バケット名（省略可）
    let outputBucketName: String?
}
