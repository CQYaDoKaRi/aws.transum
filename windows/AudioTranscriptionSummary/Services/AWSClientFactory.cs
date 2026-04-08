// AWSClientFactory.cs
// 認証方式に応じた AWS SDK 認証情報の生成を一元管理するファクトリ
// accessKey 方式と awsProfile 方式の分岐をここに集約する

#nullable enable
using System;
using Amazon;
using Amazon.Runtime;
using Amazon.Runtime.CredentialManagement;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// 現在の認証設定に基づいて AWS SDK の認証情報を生成するファクトリ。
/// authMethod に応じて BasicAWSCredentials または CredentialProfileStoreChain 経由で認証情報を生成する。
/// </summary>
public static class AWSClientFactory
{
    /// <summary>
    /// 現在の認証設定に基づいて AWSCredentials を生成する。
    ///
    /// - accessKey: settings.json の Access Key ID / Secret Access Key から BasicAWSCredentials を生成
    /// - awsProfile: CredentialProfileStoreChain を使用してプロファイルから認証情報を自動解決
    /// </summary>
    /// <param name="store">設定ストア</param>
    /// <returns>AWS 認証情報</returns>
    /// <exception cref="AppError">認証情報が無効な場合</exception>
    public static AWSCredentials MakeCredentials(SettingsStore store)
    {
        var settings = store.Load();
        var authMethod = ParseAuthMethod(settings.AuthMethod);

        switch (authMethod)
        {
            case Models.AuthMethod.AccessKey:
                // 従来の Access Key 方式
                var accessKey = settings.AccessKeyId?.Trim() ?? "";
                var secretKey = settings.SecretAccessKey?.Trim() ?? "";

                if (string.IsNullOrEmpty(accessKey) || string.IsNullOrEmpty(secretKey))
                {
                    throw new AppError(AppErrorType.CredentialsNotSet,
                        "AWS認証情報が設定されていません");
                }

                return new BasicAWSCredentials(accessKey, secretKey);

            case Models.AuthMethod.AwsProfile:
                // AWS Profile 方式: CredentialProfileStoreChain で認証情報を自動解決
                var profileName = settings.AwsProfileName?.Trim() ?? "";
                if (string.IsNullOrEmpty(profileName))
                {
                    throw new AppError(AppErrorType.CredentialsNotSet,
                        "AWSプロファイルが選択されていません");
                }

                var chain = new CredentialProfileStoreChain();
                if (chain.TryGetAWSCredentials(profileName, out var credentials))
                {
                    return credentials;
                }

                throw new AppError(AppErrorType.CredentialsNotSet,
                    $"プロファイル '{profileName}' の認証情報を解決できません。aws sso login --profile {profileName} を実行してください");

            default:
                throw new AppError(AppErrorType.CredentialsNotSet,
                    "不明な認証方式です");
        }
    }

    /// <summary>
    /// 現在の認証設定に基づいてリージョンを解決する。
    ///
    /// - awsProfile: プロファイルの region を優先、未設定時は settings.json にフォールバック
    /// - accessKey: settings.json のリージョンを使用
    /// </summary>
    /// <param name="store">設定ストア</param>
    /// <returns>リージョン文字列</returns>
    public static string ResolveRegion(SettingsStore store)
    {
        var settings = store.Load();
        var authMethod = ParseAuthMethod(settings.AuthMethod);

        if (authMethod == Models.AuthMethod.AwsProfile)
        {
            var profileName = settings.AwsProfileName?.Trim() ?? "";
            if (!string.IsNullOrEmpty(profileName))
            {
                var chain = new CredentialProfileStoreChain();
                if (chain.TryGetProfile(profileName, out var profile) &&
                    profile.Region != null)
                {
                    return profile.Region.SystemName;
                }
            }
        }

        // フォールバック: settings.json のリージョン
        return settings.Region;
    }

    /// <summary>
    /// 現在の認証設定に基づいて RegionEndpoint を解決する。
    /// </summary>
    /// <param name="store">設定ストア</param>
    /// <returns>RegionEndpoint</returns>
    public static RegionEndpoint ResolveRegionEndpoint(SettingsStore store)
    {
        return RegionEndpoint.GetBySystemName(ResolveRegion(store));
    }

    /// <summary>
    /// authMethod 文字列を AuthMethod enum に変換する。
    /// 不明な値の場合は AccessKey をデフォルトとして返す（後方互換性）。
    /// </summary>
    private static Models.AuthMethod ParseAuthMethod(string authMethodStr)
    {
        return authMethodStr?.ToLowerInvariant() switch
        {
            "awsprofile" => Models.AuthMethod.AwsProfile,
            _ => Models.AuthMethod.AccessKey
        };
    }
}
