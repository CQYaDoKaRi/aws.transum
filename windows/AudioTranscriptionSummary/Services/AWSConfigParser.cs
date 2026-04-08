// AWSConfigParser.cs
// ~/.aws/config の INI 形式を解析し、プロファイル名一覧を抽出するパーサー

#nullable enable
using System;
using System.Collections.Generic;
using System.IO;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// AWS CLI の config ファイル（INI 形式）を解析するユーティリティ。
/// [default] → "default"、[profile xxx] → "xxx" の変換ルールでプロファイル名を抽出する。
/// </summary>
public static class AWSConfigParser
{
    /// <summary>
    /// ~/.aws/config のデフォルトパスを返す（Windows: %USERPROFILE%\.aws\config）
    /// </summary>
    public static string DefaultConfigPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".aws", "config");

    /// <summary>
    /// config ファイルの内容文字列からプロファイル名一覧を抽出する。
    ///
    /// 解析ルール:
    /// - [default] → プロファイル名 "default"
    /// - [profile xxx] → プロファイル名 "xxx"
    /// - # または ; で始まる行はコメントとして無視
    /// - 空行およびキーバリューペア行はスキップ
    /// - プロファイル名の前後の空白はトリム
    /// </summary>
    /// <param name="content">config ファイルの内容文字列</param>
    /// <returns>プロファイル名のリスト（出現順）</returns>
    public static List<string> ParseProfileNames(string content)
    {
        var profiles = new List<string>();

        if (string.IsNullOrEmpty(content))
            return profiles;

        var lines = content.Split(new[] { '\n', '\r' }, StringSplitOptions.None);
        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            // 空行をスキップ
            if (string.IsNullOrEmpty(trimmed)) continue;

            // コメント行をスキップ
            if (trimmed.StartsWith('#') || trimmed.StartsWith(';')) continue;

            // セクションヘッダーの検出
            if (trimmed.StartsWith('[') && trimmed.EndsWith(']'))
            {
                var sectionContent = trimmed[1..^1].Trim();

                if (sectionContent == "default")
                {
                    // [default] → "default"
                    if (!profiles.Contains("default"))
                        profiles.Add("default");
                }
                else if (sectionContent.StartsWith("profile "))
                {
                    // [profile xxx] → "xxx"
                    var profileName = sectionContent["profile ".Length..].Trim();
                    if (!string.IsNullOrEmpty(profileName) && !profiles.Contains(profileName))
                        profiles.Add(profileName);
                }
                // その他のセクション（[sso-session xxx] 等）は無視
            }
            // キーバリューペア行はスキップ
        }

        return profiles;
    }

    /// <summary>
    /// ファイルパスからプロファイル名一覧を読み取る。
    /// </summary>
    /// <param name="path">config ファイルのパス。null の場合はデフォルトパスを使用</param>
    /// <returns>プロファイル名のリスト。ファイルが存在しない場合は空リスト</returns>
    public static List<string> LoadProfileNames(string? path = null)
    {
        var filePath = path ?? DefaultConfigPath;

        if (!File.Exists(filePath))
            return new List<string>();

        try
        {
            var content = File.ReadAllText(filePath);
            return ParseProfileNames(content);
        }
        catch
        {
            return new List<string>();
        }
    }
}
