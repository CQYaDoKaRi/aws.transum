// AWSConfigParser.swift
// ~/.aws/config の INI 形式を解析し、プロファイル名一覧を抽出するパーサー

import Foundation

// MARK: - AWSConfigParser

/// AWS CLI の config ファイル（INI 形式）を解析するユーティリティ
/// `[default]` → "default"、`[profile xxx]` → "xxx" の変換ルールでプロファイル名を抽出する
struct AWSConfigParser {

    // MARK: - デフォルトパス

    /// `~/.aws/config` のデフォルトパスを返す
    static var defaultConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aws/config"
    }

    // MARK: - パース

    /// config ファイルの内容文字列からプロファイル名一覧を抽出する
    ///
    /// 解析ルール:
    /// - `[default]` → プロファイル名 "default"
    /// - `[profile xxx]` → プロファイル名 "xxx"
    /// - `#` または `;` で始まる行はコメントとして無視
    /// - 空行およびキーバリューペア行はスキップ
    /// - プロファイル名の前後の空白はトリム
    ///
    /// - Parameter content: config ファイルの内容文字列
    /// - Returns: プロファイル名の配列（出現順）
    static func parseProfileNames(from content: String) -> [String] {
        var profiles: [String] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行をスキップ
            if trimmed.isEmpty { continue }

            // コメント行をスキップ
            if trimmed.hasPrefix("#") || trimmed.hasPrefix(";") { continue }

            // セクションヘッダーの検出
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionContent = trimmed.dropFirst().dropLast()
                    .trimmingCharacters(in: .whitespaces)

                if sectionContent == "default" {
                    // [default] → "default"
                    if !profiles.contains("default") {
                        profiles.append("default")
                    }
                } else if sectionContent.hasPrefix("profile ") {
                    // [profile xxx] → "xxx"
                    let profileName = String(sectionContent.dropFirst("profile ".count))
                        .trimmingCharacters(in: .whitespaces)
                    if !profileName.isEmpty && !profiles.contains(profileName) {
                        profiles.append(profileName)
                    }
                }
                // その他のセクション（[sso-session xxx] 等）は無視
            }
            // キーバリューペア行はスキップ
        }

        return profiles
    }

    // MARK: - ファイル読み取り

    /// ファイルパスからプロファイル名一覧を読み取る
    ///
    /// - Parameter path: config ファイルのパス。nil の場合はデフォルトパスを使用
    /// - Returns: プロファイル名の配列。ファイルが存在しない場合は空配列
    static func loadProfileNames(from path: String? = nil) -> [String] {
        let filePath = path ?? defaultConfigPath

        guard FileManager.default.fileExists(atPath: filePath) else {
            return []
        }

        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            return parseProfileNames(from: content)
        } catch {
            return []
        }
    }
}
