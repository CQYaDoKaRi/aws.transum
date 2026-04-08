// SSOAuthService.cs
// IAM Identity Center（SSO）の OIDC Device Authorization Flow を管理するサービス
// RegisterClient → StartDeviceAuthorization → CreateToken ポーリング → アカウント/ロール選択 → 一時認証情報取得

#nullable enable
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Amazon.SSO;
using Amazon.SSO.Model;
using Amazon.SSOOIDC;
using Amazon.SSOOIDC.Model;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// SSO 認証フロー全体を管理するサービスクラス（シングルトン）
/// OIDC Device Authorization Grant（RFC 8628）を使用してブラウザ経由でユーザー認証を行う
/// </summary>
public class SSOAuthService : INotifyPropertyChanged
{
    // シングルトンインスタンス
    public static SSOAuthService Instance { get; } = new SSOAuthService();

    private SSOAuthService() { }

    // MARK: - プロパティ

    private SSOLoginState _loginState = SSOLoginState.Idle;
    /// <summary>現在のログイン状態</summary>
    public SSOLoginState LoginState
    {
        get => _loginState;
        set => SetField(ref _loginState, value);
    }

    private string? _errorMessage;
    /// <summary>エラーメッセージ</summary>
    public string? ErrorMessage
    {
        get => _errorMessage;
        set => SetField(ref _errorMessage, value);
    }

    private string? _userCode;
    /// <summary>ブラウザで入力する User Code</summary>
    public string? UserCode
    {
        get => _userCode;
        set => SetField(ref _userCode, value);
    }

    private string? _verificationUri;
    /// <summary>認証 URI</summary>
    public string? VerificationUri
    {
        get => _verificationUri;
        set => SetField(ref _verificationUri, value);
    }

    private List<SSOAccountInfo> _accounts = new();
    /// <summary>利用可能なアカウント一覧</summary>
    public List<SSOAccountInfo> Accounts
    {
        get => _accounts;
        set => SetField(ref _accounts, value);
    }

    private List<string> _roles = new();
    /// <summary>選択されたアカウントで利用可能なロール一覧</summary>
    public List<string> Roles
    {
        get => _roles;
        set => SetField(ref _roles, value);
    }

    private SSOTemporaryCredentials? _temporaryCredentials;
    /// <summary>取得した一時認証情報</summary>
    public SSOTemporaryCredentials? TemporaryCredentials
    {
        get => _temporaryCredentials;
        set => SetField(ref _temporaryCredentials, value);
    }

    // MARK: - 内部状態（メモリ内のみ保持）

    /// <summary>SSO Access Token</summary>
    private string? _accessToken;
    /// <summary>Access Token の有効期限</summary>
    private DateTime? _accessTokenExpiry;
    /// <summary>SSO リージョン（認証フロー用）</summary>
    private string? _ssoRegion;

    // MARK: - キャッシュファイルパス

    private static readonly string CacheFilePath = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "AudioTranscriptionSummary", ".sso_cache.json");

    // MARK: - キャッシュ保存/復元

    /// <summary>一時認証情報をファイルにキャッシュする</summary>
    public void SaveCacheToFile()
    {
        if (TemporaryCredentials == null) return;
        try
        {
            var cache = new SSOCachedSession
            {
                AccessKeyId = TemporaryCredentials.AccessKeyId,
                SecretAccessKey = TemporaryCredentials.SecretAccessKey,
                SessionToken = TemporaryCredentials.SessionToken,
                Expiration = TemporaryCredentials.Expiration,
                AccessToken = _accessToken,
                AccessTokenExpiry = _accessTokenExpiry,
                SsoRegion = _ssoRegion
            };
            var dir = System.IO.Path.GetDirectoryName(CacheFilePath);
            if (!string.IsNullOrEmpty(dir) && !System.IO.Directory.Exists(dir))
                System.IO.Directory.CreateDirectory(dir);
            var json = System.Text.Json.JsonSerializer.Serialize(cache);
            System.IO.File.WriteAllText(CacheFilePath, json);
        }
        catch { /* キャッシュ保存失敗は致命的ではない */ }
    }

    /// <summary>ファイルからキャッシュを復元する</summary>
    public void RestoreFromCache()
    {
        if (!System.IO.File.Exists(CacheFilePath)) return;
        try
        {
            var json = System.IO.File.ReadAllText(CacheFilePath);
            var cache = System.Text.Json.JsonSerializer.Deserialize<SSOCachedSession>(json);
            if (cache == null || cache.Expiration <= DateTime.UtcNow)
            {
                ClearCache();
                return;
            }
            TemporaryCredentials = new SSOTemporaryCredentials
            {
                AccessKeyId = cache.AccessKeyId,
                SecretAccessKey = cache.SecretAccessKey,
                SessionToken = cache.SessionToken,
                Expiration = cache.Expiration
            };
            _accessToken = cache.AccessToken;
            _accessTokenExpiry = cache.AccessTokenExpiry;
            _ssoRegion = cache.SsoRegion;
            LoginState = SSOLoginState.Authenticated;
        }
        catch
        {
            ClearCache();
        }
    }

    /// <summary>キャッシュファイルを削除する</summary>
    private void ClearCache()
    {
        try { System.IO.File.Delete(CacheFilePath); } catch { }
    }

    // MARK: - Access Token 有効期限判定

    /// <summary>Access Token が有効かどうか</summary>
    public bool IsTokenValid
    {
        get
        {
            if (_accessTokenExpiry == null) return false;
            return _accessTokenExpiry.Value > DateTime.UtcNow;
        }
    }

    // MARK: - OIDC Device Authorization Flow

    /// <summary>
    /// SSO ログインを開始する
    /// RegisterClient → StartDeviceAuthorization → ブラウザ起動 → CreateToken ポーリング
    /// </summary>
    /// <param name="startUrl">IAM Identity Center の Start URL</param>
    /// <param name="region">SSO リージョン</param>
    public async Task StartLoginAsync(string startUrl, string region)
    {
        // 状態をリセット
        LoginState = SSOLoginState.Registering;
        ErrorMessage = null;
        UserCode = null;
        VerificationUri = null;
        Accounts = new List<SSOAccountInfo>();
        Roles = new List<string>();
        TemporaryCredentials = null;
        _accessToken = null;
        _accessTokenExpiry = null;
        _ssoRegion = region;

        try
        {
            // OIDC クライアントを作成
            var oidcConfig = new AmazonSSOOIDCConfig
            {
                RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(region)
            };
            using var oidcClient = new AmazonSSOOIDCClient(
                new Amazon.Runtime.AnonymousAWSCredentials(), oidcConfig);

            // 1. RegisterClient API 呼び出し
            var registerResponse = await oidcClient.RegisterClientAsync(new RegisterClientRequest
            {
                ClientName = "AudioTranscriptionSummary",
                ClientType = "public"
            });

            var clientId = registerResponse.ClientId;
            var clientSecret = registerResponse.ClientSecret;

            // 2. StartDeviceAuthorization API 呼び出し
            var deviceAuthResponse = await oidcClient.StartDeviceAuthorizationAsync(
                new StartDeviceAuthorizationRequest
                {
                    ClientId = clientId,
                    ClientSecret = clientSecret,
                    StartUrl = startUrl
                });

            var deviceCode = deviceAuthResponse.DeviceCode;
            var userCode = deviceAuthResponse.UserCode;
            var verificationUri = deviceAuthResponse.VerificationUri;
            var interval = deviceAuthResponse.Interval > 0 ? deviceAuthResponse.Interval : 5;

            // User Code を表示
            UserCode = userCode;
            VerificationUri = verificationUri;
            LoginState = SSOLoginState.WaitingForBrowser;

            // 3. ブラウザで認証 URI を開く
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = verificationUri,
                    UseShellExecute = true
                });
            }
            catch
            {
                // ブラウザ起動失敗は無視（ユーザーが手動で開ける）
            }

            // 4. CreateToken API をポーリング
            LoginState = SSOLoginState.Polling;
            var pollInterval = interval;

            while (true)
            {
                await Task.Delay(pollInterval * 1000);

                try
                {
                    var tokenResponse = await oidcClient.CreateTokenAsync(new CreateTokenRequest
                    {
                        ClientId = clientId,
                        ClientSecret = clientSecret,
                        DeviceCode = deviceCode,
                        GrantType = "urn:ietf:params:oauth:grant-type:device_code"
                    });

                    // 認証成功
                    _accessToken = tokenResponse.AccessToken;
                    if (tokenResponse.ExpiresIn > 0)
                    {
                        _accessTokenExpiry = DateTime.UtcNow.AddSeconds(tokenResponse.ExpiresIn);
                    }

                    LoginState = SSOLoginState.SelectingAccount;
                    return;
                }
                catch (AuthorizationPendingException)
                {
                    // authorization_pending: ポーリング継続
                    continue;
                }
                catch (SlowDownException)
                {
                    // slow_down: ポーリング間隔を5秒延長
                    pollInterval += 5;
                    continue;
                }
                catch (ExpiredTokenException)
                {
                    // expired_token: タイムアウト
                    ErrorMessage = "認証がタイムアウトしました。再度 SSO ログインを実行してください";
                    LoginState = SSOLoginState.Error;
                    return;
                }
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"SSO 接続に失敗しました: {ex.Message}";
            LoginState = SSOLoginState.Error;
        }
    }

    // MARK: - アカウント一覧取得

    /// <summary>SSO で利用可能なアカウント一覧を取得する</summary>
    public async Task FetchAccountsAsync()
    {
        if (_accessToken == null || !IsTokenValid)
        {
            ErrorMessage = "SSO セッションが期限切れです。再度 SSO ログインを実行してください";
            LoginState = SSOLoginState.Error;
            return;
        }
        if (_ssoRegion == null)
        {
            ErrorMessage = "SSO リージョンが設定されていません";
            LoginState = SSOLoginState.Error;
            return;
        }

        try
        {
            var ssoConfig = new AmazonSSOConfig
            {
                RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(_ssoRegion)
            };
            using var ssoClient = new AmazonSSOClient(
                new Amazon.Runtime.AnonymousAWSCredentials(), ssoConfig);

            var response = await ssoClient.ListAccountsAsync(new ListAccountsRequest
            {
                AccessToken = _accessToken
            });

            var accountList = response.AccountList ?? new List<AccountInfo>();
            Accounts = accountList
                .Where(a => !string.IsNullOrEmpty(a.AccountId) && !string.IsNullOrEmpty(a.AccountName))
                .Select(a => new SSOAccountInfo
                {
                    AccountId = a.AccountId,
                    AccountName = a.AccountName
                })
                .ToList();

            if (Accounts.Count == 0)
            {
                ErrorMessage = "利用可能なアカウントがありません。IAM Identity Center の権限設定を確認してください";
                LoginState = SSOLoginState.Error;
            }
            else
            {
                LoginState = SSOLoginState.SelectingAccount;
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"アカウント一覧の取得に失敗しました: {ex.Message}";
            LoginState = SSOLoginState.Error;
        }
    }

    // MARK: - ロール一覧取得

    /// <summary>指定アカウントで利用可能なロール一覧を取得する</summary>
    /// <param name="accountId">AWS アカウント ID</param>
    public async Task FetchRolesAsync(string accountId)
    {
        if (_accessToken == null || !IsTokenValid)
        {
            ErrorMessage = "SSO セッションが期限切れです。再度 SSO ログインを実行してください";
            LoginState = SSOLoginState.Error;
            return;
        }
        if (_ssoRegion == null)
        {
            ErrorMessage = "SSO リージョンが設定されていません";
            LoginState = SSOLoginState.Error;
            return;
        }

        try
        {
            var ssoConfig = new AmazonSSOConfig
            {
                RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(_ssoRegion)
            };
            using var ssoClient = new AmazonSSOClient(
                new Amazon.Runtime.AnonymousAWSCredentials(), ssoConfig);

            var response = await ssoClient.ListAccountRolesAsync(new ListAccountRolesRequest
            {
                AccessToken = _accessToken,
                AccountId = accountId
            });

            var roleList = response.RoleList ?? new List<RoleInfo>();
            Roles = roleList
                .Where(r => !string.IsNullOrEmpty(r.RoleName))
                .Select(r => r.RoleName)
                .ToList();

            if (Roles.Count == 0)
            {
                ErrorMessage = "このアカウントで利用可能なロールがありません";
                LoginState = SSOLoginState.Error;
            }
            else
            {
                LoginState = SSOLoginState.SelectingRole;
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"ロール一覧の取得に失敗しました: {ex.Message}";
            LoginState = SSOLoginState.Error;
        }
    }

    // MARK: - 一時認証情報取得

    /// <summary>指定アカウント・ロールの一時認証情報を取得する</summary>
    /// <param name="accountId">AWS アカウント ID</param>
    /// <param name="roleName">ロール名</param>
    public async Task FetchCredentialsAsync(string accountId, string roleName)
    {
        if (_accessToken == null || !IsTokenValid)
        {
            ErrorMessage = "SSO セッションが期限切れです。再度 SSO ログインを実行してください";
            LoginState = SSOLoginState.Error;
            return;
        }
        if (_ssoRegion == null)
        {
            ErrorMessage = "SSO リージョンが設定されていません";
            LoginState = SSOLoginState.Error;
            return;
        }

        try
        {
            var ssoConfig = new AmazonSSOConfig
            {
                RegionEndpoint = Amazon.RegionEndpoint.GetBySystemName(_ssoRegion)
            };
            using var ssoClient = new AmazonSSOClient(
                new Amazon.Runtime.AnonymousAWSCredentials(), ssoConfig);

            var response = await ssoClient.GetRoleCredentialsAsync(new GetRoleCredentialsRequest
            {
                AccessToken = _accessToken,
                AccountId = accountId,
                RoleName = roleName
            });

            var creds = response.RoleCredentials;
            if (creds == null ||
                string.IsNullOrEmpty(creds.AccessKeyId) ||
                string.IsNullOrEmpty(creds.SecretAccessKey) ||
                string.IsNullOrEmpty(creds.SessionToken))
            {
                ErrorMessage = "一時認証情報の取得に失敗しました";
                LoginState = SSOLoginState.Error;
                return;
            }

            // Expiration はミリ秒単位の Unix タイムスタンプ
            var expiration = creds.Expiration != 0
                ? DateTimeOffset.FromUnixTimeMilliseconds(creds.Expiration).UtcDateTime
                : DateTime.UtcNow.AddHours(1); // デフォルト: 1時間後

            TemporaryCredentials = new SSOTemporaryCredentials
            {
                AccessKeyId = creds.AccessKeyId,
                SecretAccessKey = creds.SecretAccessKey,
                SessionToken = creds.SessionToken,
                Expiration = expiration
            };

            LoginState = SSOLoginState.Authenticated;
            SaveCacheToFile();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"一時認証情報の取得に失敗しました: {ex.Message}";
            LoginState = SSOLoginState.Error;
        }
    }

    // MARK: - リセット

    /// <summary>ログイン状態を完全にリセットする</summary>
    public void Reset()
    {
        LoginState = SSOLoginState.Idle;
        ErrorMessage = null;
        UserCode = null;
        VerificationUri = null;
        Accounts = new List<SSOAccountInfo>();
        Roles = new List<string>();
        TemporaryCredentials = null;
        _accessToken = null;
        _accessTokenExpiry = null;
        _ssoRegion = null;
        ClearCache();
    }

    // MARK: - INotifyPropertyChanged

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }
}
