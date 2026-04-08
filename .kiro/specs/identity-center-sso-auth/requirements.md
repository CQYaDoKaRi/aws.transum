# 要件定義（Requirements）

## はじめに

AWS IAM Identity Center（SSO）による認証機能を追加する。OIDC Device Authorization Grant（RFC 8628）を使用し、アプリ内でブラウザを開いてユーザー認証を完結させる方式を採用する。既存の Access Key 方式・AWS Profile 方式に加え、3つ目の認証方式として「IAM Identity Center（SSO）」を設定画面に追加する。認証成功後はアカウント一覧・ロール一覧を取得して選択し、一時的な認証情報（Access Key / Secret Key / Session Token）を取得して AWS サービスに使用する。macOS（SwiftUI）/ Windows（WinUI 3）の両プラットフォームで同等の機能を提供する。

## 用語集（Glossary）

- **Settings_View**: アプリ設定画面（macOS: `AWSSettingsView`、Windows: `MainPage` 内の設定ダイアログ）
- **Settings_ViewModel**: 設定画面の状態管理を担当する ViewModel（macOS: `AWSSettingsViewModel`、Windows: `MainPage` 内のロジック）
- **Settings_Store**: 設定を JSON ファイルに永続化するサービス（macOS: `AppSettingsStore`、Windows: `SettingsStore`）
- **Auth_Method**: 認証方式の種別。`accessKey`（Access Key 手動入力）、`awsProfile`（AWS CLI プロファイル選択）、`sso`（IAM Identity Center SSO）のいずれか
- **SSO_Auth_Service**: OIDC Device Authorization Flow を実行するサービスモジュール。RegisterClient / StartDeviceAuthorization / CreateToken の一連の API 呼び出しを管理する
- **SSO_Client**: SSO OIDC API（RegisterClient / StartDeviceAuthorization / CreateToken）および SSO API（ListAccounts / ListAccountRoles / GetRoleCredentials）を呼び出すクライアント
- **Start_URL**: IAM Identity Center のスタート URL（例: `https://my-org.awsapps.com/start`）。ユーザーが所属する組織の SSO ポータルエンドポイント
- **SSO_Region**: IAM Identity Center が設定されている AWS リージョン（例: `us-east-1`）
- **Device_Code**: OIDC Device Authorization Flow で発行されるデバイスコード。CreateToken API のポーリングに使用する
- **User_Code**: OIDC Device Authorization Flow で発行されるユーザーコード。ブラウザ上でユーザーが入力して認証を承認する
- **Verification_URI**: ユーザーが User_Code を入力するためのブラウザ URL
- **Access_Token**: CreateToken API で取得される SSO アクセストークン。ListAccounts / ListAccountRoles / GetRoleCredentials に使用する
- **Temporary_Credentials**: GetRoleCredentials API で取得される一時的な AWS 認証情報（Access Key ID / Secret Access Key / Session Token）
- **Token_Expiry**: Access_Token の有効期限。期限切れ時に再認証が必要
- **AWS_Service_Client**: AWS SDK クライアント（S3, Transcribe, Transcribe Streaming, Translate, Bedrock Runtime）の総称
- **Connection_Tester**: AWS サービスへの接続テストを実行するモジュール

## 要件（Requirements）

### 要件 1: 認証方式の選択 UI 拡張

**ユーザーストーリー:** ユーザーとして、設定画面で Access Key / AWS Profile / IAM Identity Center（SSO）の3つの認証方式を切り替えたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Settings_View SHALL 認証情報グループ内に Auth_Method を選択する Picker に「IAM Identity Center（SSO）」を3つ目の選択肢として追加する
2. WHEN Auth_Method が `sso` の場合、THE Settings_View SHALL Start_URL 入力フィールド、SSO_Region 選択 Picker、「SSO ログイン」ボタンを表示する
3. WHEN Auth_Method が `sso` の場合、THE Settings_View SHALL Access Key ID / Secret Access Key の入力フィールドおよびプロファイル選択 Picker を非表示にする
4. WHEN Auth_Method が `accessKey` または `awsProfile` の場合、THE Settings_View SHALL 既存の動作を維持する（後方互換性）
5. THE Auth_Method Picker のデフォルト値 SHALL `accessKey` とする（既存動作との後方互換性を維持）

### 要件 2: OIDC Device Authorization Flow の実行

**ユーザーストーリー:** ユーザーとして、「SSO ログイン」ボタンを押すとブラウザが開き、認証を完了するとアプリに自動的に認証情報が反映されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが「SSO ログイン」ボタンを押した場合、THE SSO_Auth_Service SHALL RegisterClient API を呼び出し、clientId と clientSecret を取得する
2. WHEN RegisterClient が成功した場合、THE SSO_Auth_Service SHALL StartDeviceAuthorization API を呼び出し、Device_Code、User_Code、Verification_URI を取得する
3. WHEN StartDeviceAuthorization が成功した場合、THE SSO_Auth_Service SHALL Verification_URI をシステムのデフォルトブラウザで開く
4. WHEN ブラウザが開かれた場合、THE Settings_View SHALL User_Code をユーザーに表示し、「ブラウザで上記コードを入力してください」というガイダンスメッセージを表示する
5. WHEN ブラウザが開かれた場合、THE SSO_Auth_Service SHALL CreateToken API を Device_Code でポーリングし、認証完了を待機する
6. WHILE CreateToken API が `authorization_pending` エラーを返す間、THE SSO_Auth_Service SHALL StartDeviceAuthorization の interval（デフォルト5秒）に従ってポーリングを継続する
7. WHEN CreateToken API が `slow_down` エラーを返した場合、THE SSO_Auth_Service SHALL ポーリング間隔を5秒延長する
8. WHEN CreateToken API が Access_Token を返した場合、THE SSO_Auth_Service SHALL トークンと有効期限を保持し、アカウント選択フェーズに遷移する
9. IF CreateToken API が `expired_token` エラーを返した場合、THEN THE Settings_View SHALL 「認証がタイムアウトしました。再度 SSO ログインを実行してください」というエラーメッセージを表示する
10. IF RegisterClient または StartDeviceAuthorization が失敗した場合、THEN THE Settings_View SHALL エラーメッセージを表示し、ユーザーに Start_URL と SSO_Region の確認を促す
11. WHILE SSO ログインが進行中の場合、THE Settings_View SHALL プログレスインジケーターを表示し、「SSO ログイン」ボタンを無効化する

### 要件 3: アカウントとロールの選択

**ユーザーストーリー:** ユーザーとして、SSO 認証後に利用可能なアカウントとロールの一覧から選択したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Access_Token が取得された場合、THE SSO_Auth_Service SHALL ListAccounts API を呼び出し、利用可能なアカウント一覧（accountId / accountName）を取得する
2. THE Settings_View SHALL アカウント一覧を Picker の選択肢として表示する（表示形式: `accountName (accountId)`）
3. WHEN ユーザーがアカウントを選択した場合、THE SSO_Auth_Service SHALL ListAccountRoles API を呼び出し、選択されたアカウントで利用可能なロール一覧（roleName）を取得する
4. THE Settings_View SHALL ロール一覧を Picker の選択肢として表示する
5. IF ListAccounts が空の結果を返した場合、THEN THE Settings_View SHALL 「利用可能なアカウントがありません。IAM Identity Center の権限設定を確認してください」というメッセージを表示する
6. IF ListAccountRoles が空の結果を返した場合、THEN THE Settings_View SHALL 「このアカウントで利用可能なロールがありません」というメッセージを表示する

### 要件 4: 一時認証情報の取得

**ユーザーストーリー:** ユーザーとして、選択したアカウントとロールに基づいて一時的な AWS 認証情報を取得し、アプリの各機能で使用したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーがアカウントとロールを選択した場合、THE SSO_Auth_Service SHALL GetRoleCredentials API を呼び出し、Temporary_Credentials（accessKeyId / secretAccessKey / sessionToken）を取得する
2. THE AWS_Service_Client SHALL Temporary_Credentials を使用して AWS サービス（S3, Transcribe, Transcribe Streaming, Translate, Bedrock Runtime）に接続する
3. IF GetRoleCredentials が失敗した場合、THEN THE Settings_View SHALL エラーメッセージを表示する

### 要件 5: トークンの有効期限管理

**ユーザーストーリー:** ユーザーとして、トークンが期限切れになった場合に適切に通知され、再認証できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE SSO_Auth_Service SHALL Access_Token の有効期限（expiresAt）を記録する
2. WHEN AWS サービスの呼び出し前に Token_Expiry を確認し、期限切れの場合、THE Settings_View SHALL 「SSO セッションが期限切れです。再度 SSO ログインを実行してください」という通知を表示する
3. WHEN Temporary_Credentials の sessionToken が期限切れで AWS API 呼び出しが失敗した場合、THE AWS_Service_Client SHALL 「認証情報が期限切れです。設定画面から SSO ログインを再実行してください」というエラーメッセージを表示する
4. THE Settings_View SHALL SSO 認証済みの場合、トークンの残り有効時間または「認証済み」ステータスを表示する

### 要件 6: SSO 設定の永続化

**ユーザーストーリー:** ユーザーとして、SSO の設定（Start URL / SSO Region / Account ID / Role Name）がアプリ再起動後も保持されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Settings_Store SHALL `ssoStartUrl` フィールド（Start_URL）を settings.json に保存する
2. THE Settings_Store SHALL `ssoRegion` フィールド（SSO_Region）を settings.json に保存する
3. THE Settings_Store SHALL `ssoAccountId` フィールド（選択されたアカウント ID）を settings.json に保存する
4. THE Settings_Store SHALL `ssoRoleName` フィールド（選択されたロール名）を settings.json に保存する
5. WHEN アプリが起動した場合、THE Settings_ViewModel SHALL settings.json から SSO 設定を読み込み、設定画面の状態を復元する
6. WHEN `authMethod` が `sso` で SSO 設定が保存済みの場合、THE SSO_Auth_Service SHALL 保存済みの Start_URL / SSO_Region / Account ID / Role Name を使用して自動的に認証情報の取得を試みる（Access_Token が有効な場合）
7. THE Settings_Store SHALL SSO 設定の変更時に settings.json を即座に更新する

### 要件 7: SSO 方式での AWS SDK クライアント生成

**ユーザーストーリー:** ユーザーとして、SSO 認証で取得した一時認証情報がアプリの全 AWS サービスで使用されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Auth_Method が `sso` の場合、THE AWS_Service_Client SHALL Temporary_Credentials（accessKeyId / secretAccessKey / sessionToken）を使用して認証する
2. THE AWS_Service_Client SHALL SSO 方式の場合、settings.json の region（S3/Transcribe 等のサービスリージョン）を使用する（SSO_Region はあくまで SSO エンドポイント用）
3. WHEN Auth_Method が `accessKey` または `awsProfile` の場合、THE AWS_Service_Client SHALL 既存の動作を維持する（後方互換性）

### 要件 8: 接続テストの SSO 方式対応

**ユーザーストーリー:** ユーザーとして、SSO 認証方式でも接続テストを実行して動作確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Auth_Method が `sso` の場合、THE Connection_Tester SHALL Temporary_Credentials を使用して接続テストを実行する
2. IF SSO 認証が未完了の場合、THEN THE Connection_Tester SHALL 「SSO ログインを実行してください」というメッセージを表示する
3. WHEN 接続テストが成功した場合、THE Settings_View SHALL 「接続成功」のステータスを緑色で表示する
4. IF 接続テストが失敗した場合、THEN THE Settings_View SHALL エラーメッセージを赤色で表示する

### 要件 9: macOS / Windows 両対応

**ユーザーストーリー:** ユーザーとして、macOS と Windows の両方で同等の SSO 認証機能を使いたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE macOS アプリ SHALL SwiftUI の UI コンポーネントを使用して SSO 設定 UI を実装する
2. THE Windows アプリ SHALL WinUI 3 の UI コンポーネントを使用して SSO 設定 UI を実装する
3. THE macOS アプリ SHALL SSO OIDC API の呼び出しに AWS SDK for Swift の AWSSSOOIDC モジュールを使用する
4. THE Windows アプリ SHALL SSO OIDC API の呼び出しに AWS SDK for .NET の AWSSDK.SSOOIDC パッケージを使用する
5. THE macOS アプリ SHALL SSO API（ListAccounts / ListAccountRoles / GetRoleCredentials）の呼び出しに AWS SDK for Swift の AWSSSO モジュールを使用する
6. THE Windows アプリ SHALL SSO API の呼び出しに AWS SDK for .NET の AWSSDK.SSO パッケージを使用する
7. THE 両プラットフォーム SHALL ブラウザの起動にそれぞれの OS 標準 API を使用する（macOS: `NSWorkspace.shared.open`、Windows: `Process.Start`）
8. THE settings.json のスキーマ SHALL 両プラットフォームで同一のフィールド名（`ssoStartUrl`, `ssoRegion`, `ssoAccountId`, `ssoRoleName`）を使用する
