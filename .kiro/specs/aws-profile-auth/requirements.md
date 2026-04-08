# 要件定義（Requirements）

## はじめに

AWS 認証方式を従来の Access Key 手動入力に加え、AWS CLI プロファイル選択方式（IAM Identity Center / SSO 対応）にも対応する。設定画面で認証方式を切り替え可能にし、選択した認証方式とプロファイル名を settings.json に永続化する。macOS（SwiftUI）/ Windows（WinUI 3）の両プラットフォームで同等の機能を提供する。

## 用語集（Glossary）

- **Settings_View**: アプリ設定画面（macOS: `AWSSettingsView`、Windows: `MainPage` 内の設定ダイアログ）
- **Settings_ViewModel**: 設定画面の状態管理を担当する ViewModel（macOS: `AWSSettingsViewModel`、Windows: `MainPage` 内のロジック）
- **Settings_Store**: 設定を JSON ファイルに永続化するサービス（macOS: `AppSettingsStore`、Windows: `SettingsStore`）
- **Auth_Method**: 認証方式の種別。`accessKey`（Access Key 手動入力）または `awsProfile`（AWS CLI プロファイル選択）のいずれか
- **AWS_Profile**: `~/.aws/config` に定義された AWS CLI プロファイル。SSO / AssumeRole / Static credentials を含む
- **Profile_Parser**: `~/.aws/config` ファイルを解析し、プロファイル名の一覧を抽出するモジュール
- **Credential_Provider**: AWS SDK の credential provider chain を使用し、選択されたプロファイルに応じた認証情報を自動解決する仕組み
- **Connection_Tester**: AWS サービスへの接続テストを実行するモジュール（S3 への一時ファイル put/delete で検証）
- **AWS_Service_Client**: AWS SDK クライアント（S3, Transcribe, Transcribe Streaming, Translate, Bedrock Runtime）の総称

## 要件（Requirements）

### 要件 1: 認証方式の選択 UI

**ユーザーストーリー:** ユーザーとして、設定画面で Access Key 方式と AWS Profile 方式を切り替えたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Settings_View SHALL 認証情報グループ内に Auth_Method を選択する Picker（セグメントコントロール / RadioButtons）を配置する
2. WHEN Auth_Method が `accessKey` の場合、THE Settings_View SHALL Access Key ID / Secret Access Key の入力フィールドを表示する
3. WHEN Auth_Method が `awsProfile` の場合、THE Settings_View SHALL プロファイル選択 Picker を表示し、Access Key ID / Secret Access Key の入力フィールドを非表示にする
4. THE Auth_Method Picker のデフォルト値 SHALL `accessKey` とする（既存動作との後方互換性を維持）

### 要件 2: プロファイル一覧の読み取り

**ユーザーストーリー:** ユーザーとして、AWS CLI で設定済みのプロファイル一覧から選択したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Auth_Method が `awsProfile` に切り替えられた場合、THE Profile_Parser SHALL `~/.aws/config` ファイルを読み取り、定義されたプロファイル名の一覧を抽出する
2. THE Profile_Parser SHALL `[profile xxx]` セクションヘッダーからプロファイル名を抽出し、`[default]` セクションは `default` という名前で一覧に含める
3. THE Settings_View SHALL 抽出されたプロファイル名を Picker の選択肢として表示する
4. IF `~/.aws/config` ファイルが存在しない場合、THEN THE Settings_View SHALL 「AWS CLI の設定ファイルが見つかりません」というメッセージを表示する
5. IF `~/.aws/config` ファイルにプロファイルが定義されていない場合、THEN THE Settings_View SHALL 「プロファイルが見つかりません」というメッセージを表示する
6. THE Settings_View SHALL プロファイル一覧を再読み込みするリフレッシュボタンを提供する

### 要件 3: 認証方式の永続化

**ユーザーストーリー:** ユーザーとして、選択した認証方式とプロファイル名がアプリ再起動後も保持されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Settings_Store SHALL `authMethod` フィールド（`"accessKey"` または `"awsProfile"`）を settings.json に保存する
2. THE Settings_Store SHALL `awsProfileName` フィールド（選択されたプロファイル名）を settings.json に保存する
3. WHEN アプリが起動した場合、THE Settings_ViewModel SHALL settings.json から `authMethod` と `awsProfileName` を読み込み、設定画面の状態を復元する
4. WHEN `authMethod` が settings.json に存在しない場合（既存ユーザー）、THE Settings_ViewModel SHALL デフォルト値として `accessKey` を使用する
5. THE Settings_Store SHALL 認証方式の変更時に settings.json を即座に更新する

### 要件 4: プロファイルベースの AWS SDK クライアント生成

**ユーザーストーリー:** ユーザーとして、プロファイル選択時に SSO / AssumeRole / Static credentials が自動的に解決されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Auth_Method が `awsProfile` の場合、THE AWS_Service_Client SHALL AWS SDK の credential provider chain を使用し、選択されたプロファイルに応じた認証情報を自動解決する
2. WHEN Auth_Method が `accessKey` の場合、THE AWS_Service_Client SHALL 従来どおり Access Key ID / Secret Access Key を使用して認証する（既存動作を維持）
3. THE Credential_Provider SHALL プロファイルから region 設定を読み取り、settings.json のリージョン設定より優先する
4. IF プロファイルの認証情報が期限切れまたは無効の場合、THEN THE AWS_Service_Client SHALL 「認証情報が無効です。`aws sso login --profile <profile>` を実行してください」というエラーメッセージを表示する

### 要件 5: 接続テストの両方式対応

**ユーザーストーリー:** ユーザーとして、どちらの認証方式でも接続テストを実行して動作確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Auth_Method が `accessKey` の場合、THE Connection_Tester SHALL 入力された Access Key / Secret Key / Region / S3 バケット名を使用して接続テストを実行する（既存動作を維持）
2. WHEN Auth_Method が `awsProfile` の場合、THE Connection_Tester SHALL 選択されたプロファイルの credential provider chain を使用して接続テストを実行する
3. WHEN 接続テストが成功した場合、THE Settings_View SHALL 「接続成功」のステータスを緑色で表示する
4. IF 接続テストが失敗した場合、THEN THE Settings_View SHALL エラーメッセージを赤色で表示する
5. WHILE 接続テストが実行中の場合、THE Settings_View SHALL テストボタンを無効化し、プログレスインジケーターを表示する

### 要件 6: macOS / Windows 両対応

**ユーザーストーリー:** ユーザーとして、macOS と Windows の両方で同等の認証方式切り替え機能を使いたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE macOS アプリ SHALL SwiftUI の Picker / SecureField を使用して認証方式の切り替え UI を実装する
2. THE Windows アプリ SHALL WinUI 3 の RadioButtons / ComboBox を使用して認証方式の切り替え UI を実装する
3. THE macOS アプリ SHALL AWS SDK for Swift の credential provider chain（`~/.aws/config` 対応）を使用する
4. THE Windows アプリ SHALL AWS SDK for .NET の credential provider chain（`SharedCredentialsFile` / `CredentialProfileStoreChain`）を使用する
5. THE 両プラットフォーム SHALL `~/.aws/config` のパスを OS に応じて解決する（macOS: `$HOME/.aws/config`、Windows: `%USERPROFILE%\.aws\config`）
6. THE settings.json のスキーマ SHALL 両プラットフォームで同一のフィールド名（`authMethod`, `awsProfileName`）を使用する

### 要件 7: AWS Config ファイルパーサー

**ユーザーストーリー:** ユーザーとして、AWS CLI の設定ファイルが正しく解析されてプロファイル一覧が表示されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Profile_Parser SHALL INI 形式の `~/.aws/config` ファイルを解析し、`[default]` および `[profile xxx]` セクションからプロファイル名を抽出する
2. THE Profile_Parser SHALL コメント行（`#` または `;` で始まる行）を無視する
3. THE Profile_Parser SHALL 空行およびセクション内のキーバリューペアを適切にスキップする
4. FOR ALL 有効な `~/.aws/config` ファイル、パースしてプロファイル名を抽出し、再度 config 形式に整形してパースした結果 SHALL 同一のプロファイル名一覧を返す（ラウンドトリップ特性）
