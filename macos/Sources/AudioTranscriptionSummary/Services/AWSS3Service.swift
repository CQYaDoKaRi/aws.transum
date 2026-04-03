// AWSS3Service.swift
// Amazon S3 のファイルアップロード・削除を担当するサービス実装

import Foundation
import AWSS3
import SmithyIdentity
import Smithy

// MARK: - AWSS3Service（S3 クライアント実装）

/// Amazon S3 のファイル操作を担当するクラス
/// S3ClientProtocol に準拠し、putObject / deleteObject を提供する
final class AWSS3Service: S3ClientProtocol, Sendable {

    // MARK: - プロパティ

    /// AWS SDK の S3 クライアント
    private let s3Client: S3Client

    // MARK: - 初期化

    /// AWSCredentials を使用して S3 クライアントを初期化する
    /// - Parameter credentials: AWS 認証情報（accessKeyId, secretAccessKey, region）
    /// - Throws: S3 クライアントの初期化に失敗した場合
    init(credentials: AWSCredentials) throws {
        let identity = AWSCredentialIdentity(
            accessKey: credentials.accessKeyId,
            secret: credentials.secretAccessKey
        )
        let resolver = StaticAWSCredentialIdentityResolver(identity)
        let config = try S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: credentials.region
        )
        self.s3Client = S3Client(config: config)
    }

    // MARK: - S3ClientProtocol 準拠

    /// S3 バケットにファイルをアップロードする
    /// - Parameters:
    ///   - bucket: アップロード先の S3 バケット名
    ///   - key: S3 オブジェクトキー
    ///   - fileURL: アップロードするローカルファイルの URL
    /// - Throws: ファイル読み込みまたはアップロードに失敗した場合
    func putObject(bucket: String, key: String, fileURL: URL) async throws {
        let fileData = try Data(contentsOf: fileURL)
        let input = PutObjectInput(
            body: .data(fileData),
            bucket: bucket,
            key: key
        )
        _ = try await s3Client.putObject(input: input)
    }

    /// S3 バケットからオブジェクトを削除する
    /// - Parameters:
    ///   - bucket: 削除対象の S3 バケット名
    ///   - key: 削除する S3 オブジェクトキー
    /// - Throws: 削除に失敗した場合
    func deleteObject(bucket: String, key: String) async throws {
        let input = DeleteObjectInput(
            bucket: bucket,
            key: key
        )
        _ = try await s3Client.deleteObject(input: input)
    }

    // MARK: - ヘルパーメソッド

    /// AudioFile に対応する S3 オブジェクトキーを生成する
    /// UUID ベースのファイル名で衝突を防止する（`{UUID}.{拡張子}` 形式）
    /// - Parameter audioFile: 対象の音声ファイル
    /// - Returns: S3 オブジェクトキー（例: "550e8400-e29b-41d4-a716-446655440000.m4a"）
    static func generateS3Key(for audioFile: AudioFile) -> String {
        return "\(UUID().uuidString).\(audioFile.fileExtension)"
    }

    /// S3 URI を構築する
    /// - Parameters:
    ///   - bucket: S3 バケット名
    ///   - key: S3 オブジェクトキー
    /// - Returns: S3 URI（例: "s3://my-bucket/uuid.m4a"）
    static func buildS3Uri(bucket: String, key: String) -> String {
        return "s3://\(bucket)/\(key)"
    }
}
