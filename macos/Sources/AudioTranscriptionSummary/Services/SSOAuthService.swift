// SSOAuthService.swift
// IAM Identity Center（SSO）の OIDC Device Authorization Flow を管理するサービス
// RegisterClient → StartDeviceAuthorization → CreateToken ポーリング → アカウント/ロール選択 → 一時認証情報取得

import Foundation
import AWSSSOOIDC
import AWSSSO
import AppKit

// MARK: - SSOAuthService

/// SSO 認証フロー全体を管理するサービスクラス
/// OIDC Device Authorization Grant（RFC 8628）を使用してブラウザ経由でユーザー認証を行う
@MainActor
class SSOAuthService: ObservableObject {

    // MARK: - シングルトン

    /// 共有インスタンス
    static let shared = SSOAuthService()

    /// AWSClientFactory から同期的にアクセスするための一時認証情報キャッシュ
    /// @MainActor の temporaryCredentials が更新されるたびに同期される
    nonisolated(unsafe) static var cachedCredentials: SSOTemporaryCredentials?

    // MARK: - Published プロパティ

    /// 現在のログイン状態
    @Published var loginState: SSOLoginState = .idle
    /// 利用可能なアカウント一覧
    @Published var accounts: [SSOAccountInfo] = []
    /// 選択されたアカウントで利用可能なロール一覧
    @Published var roles: [String] = []
    /// 取得した一時認証情報
    @Published var temporaryCredentials: SSOTemporaryCredentials? {
        didSet {
            // AWSClientFactory から同期アクセスできるようキャッシュを更新
            SSOAuthService.cachedCredentials = temporaryCredentials
        }
    }

    // MARK: - 内部状態（メモリ内のみ保持）

    /// SSO Access Token
    private var accessToken: String?
    /// Access Token の有効期限
    private var accessTokenExpiry: Date?
    /// SSO リージョン（認証フロー用）
    private var ssoRegion: String?

    // MARK: - キャッシュファイルパス

    /// 一時認証情報のキャッシュファイルパス
    private static let cacheFilePath: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AudioTranscriptionSummary")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".sso_cache.json")
    }()

    // MARK: - キャッシュ保存/復元

    /// 一時認証情報をファイルにキャッシュする
    private func saveCacheToFile() {
        guard let creds = temporaryCredentials else { return }
        let cache = SSOCachedSession(
            credentials: creds,
            accessToken: accessToken,
            accessTokenExpiry: accessTokenExpiry,
            ssoRegion: ssoRegion
        )
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: Self.cacheFilePath, options: .atomic)
        } catch {
            // キャッシュ保存失敗は致命的ではない
        }
    }

    /// ファイルからキャッシュを復元する
    func restoreFromCache() {
        guard FileManager.default.fileExists(atPath: Self.cacheFilePath.path) else { return }
        do {
            let data = try Data(contentsOf: Self.cacheFilePath)
            let cache = try JSONDecoder().decode(SSOCachedSession.self, from: data)

            // 有効期限チェック
            guard cache.credentials.expiration > Date() else {
                // 期限切れ: キャッシュを削除
                try? FileManager.default.removeItem(at: Self.cacheFilePath)
                return
            }

            // 復元
            temporaryCredentials = cache.credentials
            accessToken = cache.accessToken
            accessTokenExpiry = cache.accessTokenExpiry
            ssoRegion = cache.ssoRegion
            loginState = .authenticated
        } catch {
            try? FileManager.default.removeItem(at: Self.cacheFilePath)
        }
    }

    /// キャッシュファイルを削除する
    private func clearCache() {
        try? FileManager.default.removeItem(at: Self.cacheFilePath)
    }

    // MARK: - Access Token 有効期限判定

    /// Access Token が有効かどうか
    var isTokenValid: Bool {
        guard let expiry = accessTokenExpiry else { return false }
        return expiry > Date()
    }

    // MARK: - OIDC Device Authorization Flow

    /// SSO ログインを開始する
    /// RegisterClient → StartDeviceAuthorization → ブラウザ起動 → CreateToken ポーリング
    /// - Parameters:
    ///   - startUrl: IAM Identity Center の Start URL
    ///   - region: SSO リージョン
    func startLogin(startUrl: String, region: String) async throws {
        // 状態をリセット
        loginState = .registering
        accounts = []
        roles = []
        temporaryCredentials = nil
        accessToken = nil
        accessTokenExpiry = nil
        ssoRegion = region

        do {
            // OIDC クライアントを作成
            let oidcConfig = try await SSOOIDCClient.SSOOIDCClientConfiguration(region: region)
            let oidcClient = SSOOIDCClient(config: oidcConfig)

            // 1. RegisterClient API 呼び出し
            let registerInput = RegisterClientInput(
                clientName: "AudioTranscriptionSummary",
                clientType: "public"
            )
            let registerOutput = try await oidcClient.registerClient(input: registerInput)

            guard let clientId = registerOutput.clientId,
                  let clientSecret = registerOutput.clientSecret else {
                throw SSOAuthError.registerClientFailed
            }

            // 2. StartDeviceAuthorization API 呼び出し
            let deviceAuthInput = StartDeviceAuthorizationInput(
                clientId: clientId,
                clientSecret: clientSecret,
                startUrl: startUrl
            )
            let deviceAuthOutput = try await oidcClient.startDeviceAuthorization(input: deviceAuthInput)

            guard let deviceCode = deviceAuthOutput.deviceCode,
                  let userCode = deviceAuthOutput.userCode,
                  let verificationUri = deviceAuthOutput.verificationUri else {
                throw SSOAuthError.startDeviceAuthorizationFailed
            }

            let interval = deviceAuthOutput.interval ?? 5

            // 3. ブラウザで認証 URI を開く
            if let url = URL(string: verificationUri) {
                NSWorkspace.shared.open(url)
            }

            // User Code を表示（ポーリング中も維持）
            loginState = .waitingForBrowser(userCode: userCode, verificationUri: verificationUri)

            // 4. CreateToken API をポーリング（loginState は .waitingForBrowser のまま維持）
            var pollInterval = TimeInterval(interval)

            while true {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))

                do {
                    let tokenInput = CreateTokenInput(
                        clientId: clientId,
                        clientSecret: clientSecret,
                        deviceCode: deviceCode,
                        grantType: "urn:ietf:params:oauth:grant-type:device_code"
                    )
                    let tokenOutput = try await oidcClient.createToken(input: tokenInput)

                    // 認証成功
                    guard let token = tokenOutput.accessToken else {
                        throw SSOAuthError.createTokenFailed
                    }

                    accessToken = token
                    let expiresIn = tokenOutput.expiresIn
                    if expiresIn > 0 {
                        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
                    }

                    loginState = .selectingAccount
                    return

                } catch let error as AuthorizationPendingException {
                    // authorization_pending: ポーリング継続
                    _ = error
                    continue
                } catch let error as SlowDownException {
                    // slow_down: ポーリング間隔を5秒延長
                    _ = error
                    pollInterval += 5
                    continue
                } catch let error as ExpiredTokenException {
                    // expired_token: タイムアウト
                    _ = error
                    loginState = .error("認証がタイムアウトしました。再度 SSO ログインを実行してください")
                    return
                }
            }

        } catch let error as SSOAuthError {
            loginState = .error(error.localizedDescription)
        } catch {
            loginState = .error("SSO 接続に失敗しました: \(error.localizedDescription)")
        }
    }


    // MARK: - アカウント一覧取得

    /// SSO で利用可能なアカウント一覧を取得する
    func fetchAccounts() async throws {
        guard let token = accessToken, isTokenValid else {
            loginState = .error("SSO セッションが期限切れです。再度 SSO ログインを実行してください")
            return
        }
        guard let region = ssoRegion else {
            loginState = .error("SSO リージョンが設定されていません")
            return
        }

        do {
            let ssoConfig = try await SSOClient.SSOClientConfiguration(region: region)
            let ssoClient = SSOClient(config: ssoConfig)

            let input = ListAccountsInput(accessToken: token)
            let output = try await ssoClient.listAccounts(input: input)

            let accountList = output.accountList ?? []
            accounts = accountList.compactMap { account in
                guard let accountId = account.accountId,
                      let accountName = account.accountName else { return nil }
                return SSOAccountInfo(accountId: accountId, accountName: accountName)
            }

            if accounts.isEmpty {
                loginState = .error("利用可能なアカウントがありません。IAM Identity Center の権限設定を確認してください")
            } else {
                loginState = .selectingAccount
            }
        } catch {
            loginState = .error("アカウント一覧の取得に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - ロール一覧取得

    /// 指定アカウントで利用可能なロール一覧を取得する
    /// - Parameter accountId: AWS アカウント ID
    func fetchRoles(accountId: String) async throws {
        guard let token = accessToken, isTokenValid else {
            loginState = .error("SSO セッションが期限切れです。再度 SSO ログインを実行してください")
            return
        }
        guard let region = ssoRegion else {
            loginState = .error("SSO リージョンが設定されていません")
            return
        }

        do {
            let ssoConfig = try await SSOClient.SSOClientConfiguration(region: region)
            let ssoClient = SSOClient(config: ssoConfig)

            let input = ListAccountRolesInput(accessToken: token, accountId: accountId)
            let output = try await ssoClient.listAccountRoles(input: input)

            let roleList = output.roleList ?? []
            roles = roleList.compactMap { $0.roleName }

            if roles.isEmpty {
                loginState = .error("このアカウントで利用可能なロールがありません")
            } else {
                loginState = .selectingRole
            }
        } catch {
            loginState = .error("ロール一覧の取得に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - 一時認証情報取得

    /// 指定アカウント・ロールの一時認証情報を取得する
    /// - Parameters:
    ///   - accountId: AWS アカウント ID
    ///   - roleName: ロール名
    func fetchCredentials(accountId: String, roleName: String) async throws {
        guard let token = accessToken, isTokenValid else {
            loginState = .error("SSO セッションが期限切れです。再度 SSO ログインを実行してください")
            return
        }
        guard let region = ssoRegion else {
            loginState = .error("SSO リージョンが設定されていません")
            return
        }

        do {
            let ssoConfig = try await SSOClient.SSOClientConfiguration(region: region)
            let ssoClient = SSOClient(config: ssoConfig)

            let input = GetRoleCredentialsInput(
                accessToken: token,
                accountId: accountId,
                roleName: roleName
            )
            let output = try await ssoClient.getRoleCredentials(input: input)

            guard let creds = output.roleCredentials,
                  let accessKeyId = creds.accessKeyId,
                  let secretAccessKey = creds.secretAccessKey,
                  let sessionToken = creds.sessionToken else {
                throw SSOAuthError.getRoleCredentialsFailed
            }

            // expiration はミリ秒単位の Unix タイムスタンプ
            let expiration: Date
            if creds.expiration != 0 {
                expiration = Date(timeIntervalSince1970: TimeInterval(creds.expiration) / 1000.0)
            } else {
                // デフォルト: 1時間後
                expiration = Date().addingTimeInterval(3600)
            }

            temporaryCredentials = SSOTemporaryCredentials(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                sessionToken: sessionToken,
                expiration: expiration
            )

            // キャッシュをファイルに保存
            saveCacheToFile()

            loginState = .authenticated
        } catch let error as SSOAuthError {
            loginState = .error(error.localizedDescription)
        } catch {
            loginState = .error("一時認証情報の取得に失敗しました: \(error.localizedDescription)")
        }
    }

    // MARK: - リセット

    /// ログイン状態を完全にリセットする
    func reset() {
        loginState = .idle
        accounts = []
        roles = []
        temporaryCredentials = nil
        accessToken = nil
        accessTokenExpiry = nil
        ssoRegion = nil
        clearCache()
    }
}

// MARK: - SSOAuthError

/// SSO 認証フローのエラー
enum SSOAuthError: LocalizedError {
    case registerClientFailed
    case startDeviceAuthorizationFailed
    case createTokenFailed
    case getRoleCredentialsFailed

    var errorDescription: String? {
        switch self {
        case .registerClientFailed:
            return "SSO 接続に失敗しました。Start URL と SSO リージョンを確認してください"
        case .startDeviceAuthorizationFailed:
            return "デバイス認証の開始に失敗しました。Start URL を確認してください"
        case .createTokenFailed:
            return "認証に失敗しました。再度 SSO ログインを実行してください"
        case .getRoleCredentialsFailed:
            return "一時認証情報の取得に失敗しました"
        }
    }
}
