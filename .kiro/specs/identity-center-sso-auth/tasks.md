# 実装計画: IAM Identity Center（SSO）認証方式対応

## 概要

AWS IAM Identity Center（SSO）による認証機能を追加する。OIDC Device Authorization Grant（RFC 8628）フローを使用し、ブラウザ経由でユーザー認証を行い、一時的な AWS 認証情報を取得する。既存の Access Key / AWS Profile 方式に加え、3つ目の認証方式として `sso` を追加する。macOS（Swift）を先行実装し、その後 Windows（C#）に適用する。

## Tasks

- [-] 1. macOS: データモデルと依存パッケージの追加
  - [ ] 1.1 `AuthMethod` enum に `.sso` ケースを追加
    - `Models/AuthMethod.swift` に `case sso = "sso"` を追加
    - `displayName` に `"IAM Identity Center"` を返すケースを追加
    - _Requirements: 1.1, 1.5_

  - [ ] 1.2 `AppSettings` に SSO 関連フィールドを追加
    - `Services/AppSettingsStore.swift` の `AppSettings` struct に `ssoStartUrl`, `ssoRegion`, `ssoAccountId`, `ssoRoleName` フィールドを追加（デフォルト値 `""`）
    - 既存の `Codable` 準拠で自動対応
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

  - [ ] 1.3 `Package.swift` に AWSSSOOIDC / AWSSSO 依存を追加
    - `dependencies` に `.product(name: "AWSSSOOIDC", package: "aws-sdk-swift")` と `.product(name: "AWSSSO", package: "aws-sdk-swift")` を追加
    - _Requirements: 9.3, 9.5_

  - [ ]* 1.4 Property 1: SSO 設定永続化ラウンドトリップのプロパティテスト
    - **Property 1: SSO 設定永続化のラウンドトリップ**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4**
    - SwiftCheck でランダムな `AppSettings`（`authMethod` = `"sso"`、`ssoStartUrl` / `ssoRegion` / `ssoAccountId` / `ssoRoleName` 含む）を一時ディレクトリに save → load → 全フィールド一致を検証


- [ ] 2. macOS: SSOAuthService の実装
  - [ ] 2.1 SSO 関連データモデルの作成
    - `Models/SSOModels.swift` を新規作成
    - `SSOLoginState` enum（`idle`, `registering`, `waitingForBrowser`, `polling`, `selectingAccount`, `selectingRole`, `authenticated`, `error`）を定義
    - `SSOAccountInfo` struct（`accountId`, `accountName`, `displayName`）を定義
    - `SSOTemporaryCredentials` struct（`accessKeyId`, `secretAccessKey`, `sessionToken`, `expiration`）を定義
    - _Requirements: 3.1, 3.2, 4.1_

  - [ ] 2.2 `SSOAuthService` コアロジックの実装
    - `Services/SSOAuthService.swift` を新規作成
    - `@MainActor class SSOAuthService: ObservableObject` として実装
    - `startLogin(startUrl:region:)`: RegisterClient → StartDeviceAuthorization → ブラウザ起動 → CreateToken ポーリングの一連のフローを実装
    - RegisterClient API で `clientId` / `clientSecret` を取得
    - StartDeviceAuthorization API で `deviceCode` / `userCode` / `verificationUri` を取得
    - `NSWorkspace.shared.open()` で `verificationUri` をブラウザで開く
    - CreateToken API を `interval` 秒ごとにポーリング（`authorization_pending` で継続、`slow_down` で間隔+5秒）
    - `expired_token` エラー時にタイムアウトメッセージを設定
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 9.7_

  - [ ] 2.3 `SSOAuthService` アカウント・ロール・認証情報取得の実装
    - `fetchAccounts()`: ListAccounts API で利用可能なアカウント一覧を取得
    - `fetchRoles(accountId:)`: ListAccountRoles API で指定アカウントのロール一覧を取得
    - `fetchCredentials(accountId:roleName:)`: GetRoleCredentials API で一時認証情報を取得
    - `isTokenValid`: Access Token の有効期限を判定
    - `reset()`: ログイン状態をリセット
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 4.1, 4.3, 5.1_

  - [ ]* 2.4 Property 2: SSOAccountInfo displayName フォーマットのプロパティテスト
    - **Property 2: SSOAccountInfo の表示名フォーマット**
    - **Validates: Requirements 3.2**
    - SwiftCheck でランダムな `accountName` / `accountId` から `displayName` が `"{accountName} ({accountId})"` 形式であることを検証

  - [ ]* 2.5 Property 3: トークン有効期限判定のプロパティテスト
    - **Property 3: トークン有効期限の判定**
    - **Validates: Requirements 5.1, 5.2**
    - ランダムな `expiresAt`（現在時刻 ± 3600秒）に対して `isTokenValid` が `expiresAt > Date()` と一致することを検証

  - [ ]* 2.6 `SSOAuthService` のユニットテスト
    - `AuthMethod` enum の `.sso` ケースの `displayName` / シリアライゼーション検証
    - `SSOAuthService.reset()` で状態が `idle` に戻ることを検証
    - 空アカウント一覧 / 空ロール一覧時のエラーメッセージ設定を検証
    - _Requirements: 2.9, 2.10, 3.5, 3.6_


- [ ] 3. macOS: AWSClientFactory の SSO 方式対応
  - [ ] 3.1 `AWSClientFactory` に SSO 分岐を追加
    - `Services/AWSClientFactory.swift` の `makeCredentialResolver()` に `case .sso` 分岐を追加
    - `SSOAuthService.shared.temporaryCredentials` からメモリ内の一時認証情報を取得
    - `sessionToken` を含む `AWSCredentialIdentity` を生成して `StaticAWSCredentialIdentityResolver` を返す
    - SSO 未認証時に `AWSClientFactoryError.ssoNotAuthenticated` をスロー
    - credentials 期限切れ時に `AWSClientFactoryError.ssoTokenExpired` をスロー
    - `currentRegion()` は SSO 方式の場合 `settings.region`（サービスリージョン）を使用
    - _Requirements: 4.2, 7.1, 7.2, 7.3_

  - [ ]* 3.2 Property 4: AWSClientFactory SSO credentials 変換のプロパティテスト
    - **Property 4: AWSClientFactory の SSO credentials 変換**
    - **Validates: Requirements 4.2, 7.1**
    - ランダムな `SSOTemporaryCredentials`（非空 accessKeyId / secretAccessKey / sessionToken、未来の expiration）に対して `makeCredentialResolver()` が返す resolver の identity が元の値と一致することを検証

  - [ ]* 3.3 `AWSClientFactory` SSO 分岐のユニットテスト
    - SSO 未認証時に `ssoNotAuthenticated` エラーがスローされることを検証
    - credentials 期限切れ時に `ssoTokenExpired` エラーがスローされることを検証
    - `currentRegion()` が SSO 方式の場合に `settings.region` を返すことを検証
    - _Requirements: 7.1, 7.2, 7.3_

- [ ] 4. macOS: 設定画面 UI の SSO 対応
  - [ ] 4.1 `AWSSettingsViewModel` の SSO 関連プロパティ追加
    - `@Published var ssoStartUrl: String`, `ssoRegion: String`, `ssoAccountId: String`, `ssoRoleName: String` を追加
    - `@Published var ssoAuthService: SSOAuthService` を追加（shared instance）
    - `loadAll()` で SSO 設定を settings.json から復元
    - `setupAutoSave()` に SSO 関連フィールドの変更監視を追加
    - `saveToFile()` に SSO フィールドの保存を追加
    - `updateSavedState()` に SSO 方式の判定を追加（`ssoStartUrl` が非空かつ認証済み）
    - `testConnection()` に SSO 方式の分岐を追加（Temporary Credentials で S3 接続テスト）
    - SSO 未認証時の接続テストで「SSO ログインを実行してください」メッセージ
    - _Requirements: 5.2, 5.4, 6.5, 6.7, 8.1, 8.2, 8.3, 8.4_

  - [ ] 4.2 `AWSSettingsView` に SSO 設定 UI を追加
    - 認証方式 Picker に「IAM Identity Center」を3つ目の選択肢として追加
    - SSO 選択時: Start URL テキストフィールド、SSO Region Picker、「SSO ログイン」ボタンを表示
    - SSO 選択時: Access Key / プロファイル選択 UI を非表示
    - User Code 表示ラベル + 「ブラウザで上記コードを入力してください」ガイダンスメッセージ
    - ポーリング中のプログレスインジケーター + ボタン無効化
    - アカウント Picker（認証成功後に表示、形式: `accountName (accountId)`）
    - ロール Picker（アカウント選択後に表示）
    - 認証ステータス表示（「認証済み」/ 残り有効時間 / エラーメッセージ）
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.4, 2.11, 3.2, 3.4, 5.4, 9.1_


- [ ] 5. macOS: トークン有効期限管理と自動再認証
  - [ ] 5.1 トークン有効期限チェックの統合
    - `SSOAuthService` に `checkAndRefreshIfNeeded()` メソッドを追加
    - AWS サービス呼び出し前に `isTokenValid` を確認し、期限切れ時にエラー通知
    - `AWSClientFactory.makeCredentialResolver()` 内で `expiration` チェックを実施
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ] 5.2 アプリ起動時の SSO 設定復元
    - `AWSSettingsViewModel.loadAll()` で `authMethod == .sso` かつ SSO 設定が保存済みの場合、`SSOAuthService` に設定を復元
    - Access Token はメモリ内のみ保持のため、起動時は未認証状態（ユーザーに再ログインを促す）
    - _Requirements: 6.5, 6.6_

- [x] 6. チェックポイント - macOS 実装の検証
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

- [ ] 7. Windows: データモデルと依存パッケージの追加
  - [ ] 7.1 `AuthMethod` enum に `Sso` ケースを追加
    - `Models/AuthMethod.cs` に `Sso` を追加
    - _Requirements: 1.1, 1.5_

  - [ ] 7.2 `AppSettings` に SSO 関連フィールドを追加
    - `Models/AppSettings.cs` に `SsoStartUrl`, `SsoRegion`, `SsoAccountId`, `SsoRoleName` プロパティを追加（`[JsonPropertyName]` 属性付き、デフォルト値 `""`）
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 9.8_

  - [ ] 7.3 `.csproj` に AWSSDK.SSOOIDC / AWSSDK.SSO 依存を追加
    - `AudioTranscriptionSummary.csproj` に `<PackageReference Include="AWSSDK.SSOOIDC" Version="4.*" />` と `<PackageReference Include="AWSSDK.SSO" Version="4.*" />` を追加
    - _Requirements: 9.4, 9.6_

- [ ] 8. Windows: SSOAuthService の実装
  - [ ] 8.1 SSO 関連データモデルの作成
    - `Models/SSOModels.cs` を新規作成
    - `SSOLoginState` enum、`SSOAccountInfo` class、`SSOTemporaryCredentials` class を定義
    - macOS 版と同等のデータ構造
    - _Requirements: 3.1, 3.2, 4.1_

  - [ ] 8.2 `SSOAuthService` の実装（C#）
    - `Services/SSOAuthService.cs` を新規作成
    - `INotifyPropertyChanged` を実装
    - `StartLoginAsync(startUrl, region)`: RegisterClient → StartDeviceAuthorization → ブラウザ起動（`Process.Start`）→ CreateToken ポーリング
    - `FetchAccountsAsync()`: ListAccounts API でアカウント一覧取得
    - `FetchRolesAsync(accountId)`: ListAccountRoles API でロール一覧取得
    - `FetchCredentialsAsync(accountId, roleName)`: GetRoleCredentials API で一時認証情報取得
    - `IsTokenValid` プロパティ: Access Token の有効期限判定
    - `Reset()`: ログイン状態リセット
    - _Requirements: 2.1〜2.11, 3.1〜3.6, 4.1, 4.3, 5.1, 9.7_


- [ ] 9. Windows: AWSClientFactory の SSO 方式対応
  - [ ] 9.1 `AWSClientFactory` に SSO 分岐を追加
    - `Services/AWSClientFactory.cs` の `MakeCredentials()` に `case Models.AuthMethod.Sso` 分岐を追加
    - `SSOAuthService.Instance.TemporaryCredentials` から `SessionAWSCredentials` を生成
    - SSO 未認証時 / credentials 期限切れ時のエラーハンドリング
    - `ParseAuthMethod()` に `"sso"` → `Models.AuthMethod.Sso` のマッピングを追加
    - _Requirements: 4.2, 7.1, 7.2, 7.3_

- [ ] 10. Windows: 設定ダイアログ UI の SSO 対応
  - [ ] 10.1 設定ダイアログに SSO 設定 UI を追加
    - `Views/MainPage.xaml.cs` の `OnSettingsClick` 内に SSO 認証方式の `RadioButton` を追加
    - SSO 選択時: Start URL `TextBox`、SSO Region `ComboBox`、「SSO ログイン」`Button` を表示
    - SSO 選択時: Access Key / プロファイル選択 UI を非表示
    - User Code 表示 + ガイダンスメッセージ
    - ポーリング中の `ProgressRing` + ボタン無効化
    - アカウント `ComboBox`（認証成功後に表示）
    - ロール `ComboBox`（アカウント選択後に表示）
    - 認証ステータス表示
    - 設定保存時に SSO フィールドを `settings.json` に永続化
    - 接続テストの SSO 方式対応
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.4, 2.11, 3.2, 3.4, 5.4, 8.1, 8.2, 8.3, 8.4, 9.2_

- [x] 11. チェックポイント - Windows 実装の検証
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

- [ ] 12. 最終統合と後方互換性の確認
  - [ ] 12.1 後方互換性テスト
    - `ssoStartUrl` 等のフィールドなしの既存 `settings.json` をデシリアライズし、デフォルト値 `""` が使用されることを確認（macOS / Windows 両方）
    - `authMethod` が `"sso"` 以外の場合、SSO フィールドが無視されることを確認
    - Access Key / AWS Profile 方式の既存動作が変更されていないことを確認
    - _Requirements: 1.4, 1.5_

  - [ ] 12.2 settings.json スキーマの整合性確認
    - macOS / Windows 両方で `ssoStartUrl` / `ssoRegion` / `ssoAccountId` / `ssoRoleName` フィールド名が同一であることを確認
    - _Requirements: 9.8_

- [x] 13. 最終チェックポイント
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

## Notes

- `*` 付きのタスクはオプションであり、MVP では省略可能
- macOS（Swift）を先行実装し、Windows（C#）に適用する順序で構成
- 各タスクは要件番号を参照しトレーサビリティを確保
- プロパティテストは SwiftCheck（macOS）を使用
- Access Token はメモリ内のみ保持（ディスクには保存しない）
- 既存の Access Key / AWS Profile 方式は完全に維持（後方互換性）
- SSO OIDC API の実際の呼び出しは統合テスト（手動）で検証
