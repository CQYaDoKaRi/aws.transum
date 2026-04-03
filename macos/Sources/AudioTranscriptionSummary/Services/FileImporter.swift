// FileImporter.swift
// 音声・動画ファイルの読み込みとバリデーションを担当するサービス
// サポート形式: m4a, wav, mp3, aiff, mp4, mov, m4v

import AVFoundation
import Foundation

// MARK: - FileImporter（ファイル読み込みサービス）

/// FileImporting プロトコルに準拠したメディアファイル読み込みサービス
/// AVFoundation を用いてファイルのメタデータ取得とバリデーションを行う
/// 動画ファイルの場合は音声トラックの存在を確認する
final class FileImporter: FileImporting, Sendable {

    // MARK: - サポート対象形式

    /// サポートされる音声ファイル形式の拡張子一覧
    static let supportedExtensions: Set<String> = ["m4a", "wav", "mp3", "aiff", "mp4", "mov", "m4v"]

    /// 動画ファイルの拡張子一覧
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    // MARK: - 形式判定

    /// ファイル形式がサポート対象かを判定する
    /// - Parameter fileExtension: 判定するファイル拡張子（大文字小文字を区別しない）
    /// - Returns: サポート対象であれば true
    func isSupported(fileExtension: String) -> Bool {
        Self.supportedExtensions.contains(fileExtension.lowercased())
    }

    // MARK: - ファイル読み込み

    /// 音声ファイルを読み込み、AudioFile モデルを返す
    ///
    /// バリデーション処理フロー:
    /// 1. ファイル拡張子の確認（サポート対象形式か）
    /// 2. ファイルの読み込み可否確認（破損チェック）
    /// 3. AVAsset を用いたメタデータ（再生時間）の取得
    /// 4. AudioFile モデルの生成
    ///
    /// - Parameter url: 読み込む音声ファイルの URL
    /// - Returns: 読み込まれた AudioFile
    /// - Throws: `AppError.unsupportedFormat` または `AppError.corruptedFile`
    func importFile(from url: URL) async throws -> AudioFile {
        // 1. ファイル拡張子の確認
        let ext = url.pathExtension.lowercased()
        guard isSupported(fileExtension: ext) else {
            let supportedList = Self.supportedExtensions.sorted()
            throw AppError.unsupportedFormat(ext, supportedFormats: supportedList)
        }

        // 2. ファイルの読み込み可否確認（存在チェック）
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw AppError.corruptedFile
        }

        // 3. AVAsset を用いたメタデータ取得
        let asset = AVAsset(url: url)

        // 再生時間の取得（破損ファイルの場合はエラー）
        let duration: TimeInterval
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
            // 再生時間が無効な場合は破損とみなす
            guard duration.isFinite, duration > 0 else {
                throw AppError.corruptedFile
            }
        } catch let error as AppError {
            throw error
        } catch {
            // AVAsset の読み込みに失敗した場合は破損とみなす
            throw AppError.corruptedFile
        }

        // ファイルサイズの取得
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            throw AppError.corruptedFile
        }

        // 4. AudioFile モデルの生成
        let fileName = url.deletingPathExtension().lastPathComponent
        return AudioFile(
            id: UUID(),
            url: url,
            fileName: fileName,
            fileExtension: ext,
            duration: duration,
            fileSize: fileSize,
            createdAt: Date()
        )
    }
}
