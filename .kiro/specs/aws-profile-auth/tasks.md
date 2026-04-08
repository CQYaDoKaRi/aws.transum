# 実装計画: AWS Profile 認証方式対応

## 概要

AWS 認証方式を従来の Access Key 手動入力に加え、AWS CLI プロファイル選択方式（SSO / AssumeRole 対応）に拡張する。macOS（Swift）を先行実装し、その後 Windows（C#）に適用する。各サービスクライアントの認証情報生成を `AWSClientFactory` に集約し、`authMethod` に応じた分岐を一元管理する。

## Tasks

- [-] 1. macOS: データモデルとパーサーの実装
  - [ ] 1.1 `AuthMethod` enum と `AppSettings` の拡張
    - `Models/AuthMethod.swift` に `AuthMethod` enum（`accessKey` / `awsProfile`）を作成
    - `AppSettings` に `authMethod: String` と `awsProfileName: String` フィールドを追加（デフォルト値 `"accessKey"` / `""`）
    - `AppSettingsStore` の save/load は既存の `Codable` で自動対応
    - _Requirements: 3.1, 3.2, 3.4_

  - [ ] 1.2 `AWSConfigParser` の実装
    - `Services/AWSConfigParser.swift` を新規作成
    - `parseProfileNames(from content: String) -> [String]`: INI 形式の config 文字列からプロファイル名を抽出
    - `[default]` → `"default"`、`[profile xxx]` → `"xxx"` の変換ルール
    - コメント行（`#` / `;`）、空行、キーバリューペア行をスキップ
    - `defaultConfigPath`: `$HOME/.aws/config` を返す static プロパティ
    - `loadProfileNames(from path: String?) -> [String]`: ファイルパスからプロファイル名一覧を読み取り
    - _Requirements: 2.1, 2.2, 7.1, 7.2, 7.3_

  - [ ]* 1.3 `AWSConfigParser` のユニットテスト
    - 空ファイル、コメントのみ、default のみ、複数プロファイル、コメント混在のケースをテスト
    - ファイル不存在時の空配列返却を検証
    - _Requirements: 2.1, 2.2, 2.4, 7.1, 7.2, 7.3_

  - [ ]* 1.4 Property 1: Config パーサーラウンドトリップのプロパティテスト
    - **Property 1: AWS Config パーサーのラウンドトリップ**
    - **Validates: Requirements 2.1, 2.2, 7.1, 7.2, 7.3, 7.4**
    - SwiftCheck でランダムなプロファイル名セットから config 文字列を生成 → パース → 元セットと一致を検証
    - コメント行・空行・キーバリューペアをランダム挿入

  - [ ]* 1.5 Property 2: 設定永続化ラウンドトリップのプロパティテスト
    - **Property 2: 設定永続化のラウンドトリップ（authMethod / awsProfileName）**
    - **Validates: Requirements 3.1, 3.2, 3.3**
    - ランダムな `AppSettings`（authMethod, awsProfileName 含む）を一時ディレクトリに save → load → 全フィールド一致を検証

- [ ] 2. macOS: プロファイルベース認証情報解決の実装
  - [ ] 2.1 `AWSProfileCredentialHelper` の実装
    - `Services/AWSProfileCredentialHelper.swift` を新規作成
    - `resolveCredentials(profileName:)`: `~/.aws/credentials` と `~/.aws/config` から access_key / secret_key / session_token を直接読み取り
    - SSO プロファイル等で静的キーが存在しない場合は `AWS_PROFILE` 環境変数を設定して SDK デフォルトに委譲
    - `resolveRegion(profileName:)`: プロファイルの region 設定を読み取り
    - _Requirements: 4.1, 4.3, 4.4_

  - [ ] 2.2 `AWSClientFactory` の実装
    - `Services/AWSClientFactory.swift` を新規作成
    - `makeCredentialResolver()`: `AppSettingsStore` から `authMethod` を読み取り、`accessKey` なら `StaticAWSCredentialIdentityResolver`、`awsProfile` なら `AWSProfileCredentialHelper` 経由で resolver を生成
    - `currentRegion()`: プロファイルの region を優先し、未設定時は settings.json のリージョンにフォールバック
    - _Requirements: 4.1, 4.2, 4.3_

  - [ ] 2.3 既存サービスの認証情報生成を `AWSClientFactory` に統合
    - `Summarizer.swift`: `summarizeWithBedrock` 内の `StaticAWSCredentialIdentityResolver` 生成を `AWSClientFactory.makeCredentialResolver()` に置換
    - `AWSS3Service.swift`: イニシャライザの認証情報解決を `AWSClientFactory` 経由に変更
    - `TranscribeClient.swift`: `validateCredentials()` を `authMethod` に応じた分岐に拡張
    - `RealtimeTranscribeClient.swift`: `startStreaming` 内の認証情報解決を `AWSClientFactory` 経由に変更
    - `TranslateService.swift`: クライアント生成を `AWSClientFactory` 経由に変更
    - `AWSSettingsViewModel.swift`: `hasValidCredentials` / `loadAWSCredentials()` を `authMethod` に応じて分岐
    - _Requirements: 4.1, 4.2, 5.1, 5.2_

- [ ] 3. macOS: 設定画面 UI の実装
  - [ ] 3.1 `AWSSettingsViewModel` の拡張
    - `@Published var authMethod: AuthMethod` / `selectedProfileName: String` / `availableProfiles: [String]` / `profileLoadError: String?` を追加
    - `loadProfiles()`: `AWSConfigParser.loadProfileNames()` を呼び出してプロファイル一覧を取得
    - `refreshProfiles()`: リフレッシュボタン用（`loadProfiles()` を再実行）
    - `authMethod` 変更時に `saveToFile()` を即座に実行（既存の Combine 自動保存に追加）
    - `authMethod` が `awsProfile` に切り替わった時に `loadProfiles()` を自動実行
    - _Requirements: 1.1, 1.4, 2.1, 2.6, 3.3, 3.5_

  - [ ] 3.2 `AWSSettingsView` の認証方式切り替え UI
    - 認証情報グループ内に `Picker`（セグメントコントロール）で `accessKey` / `awsProfile` を切り替え
    - `accessKey` 選択時: 既存の Access Key ID / Secret Access Key フィールドを表示
    - `awsProfile` 選択時: プロファイル選択 Picker + リフレッシュボタンを表示、Access Key フィールドを非表示
    - `~/.aws/config` 不存在時: 「AWS CLI の設定ファイルが見つかりません」メッセージ表示
    - プロファイル未定義時: 「プロファイルが見つかりません」メッセージ表示
    - _Requirements: 1.1, 1.2, 1.3, 2.3, 2.4, 2.5, 2.6, 6.1_

  - [ ] 3.3 接続テストの両方式対応
    - `testConnection()` を `authMethod` に応じて分岐
    - `accessKey`: 既存の Access Key ベースの接続テスト（変更なし）
    - `awsProfile`: `AWSClientFactory` 経由の credential resolver で S3 接続テスト
    - プロファイル認証失敗時: 「認証情報が無効です。`aws sso login --profile <profile>` を実行してください」メッセージ
    - テスト中のプログレスインジケーター・ボタン無効化は既存実装を維持
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [x] 4. チェックポイント - macOS 実装の検証
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

- [ ] 5. Windows: データモデルとパーサーの実装
  - [ ] 5.1 `AuthMethod` enum と `AppSettings` の拡張
    - `Models/AuthMethod.cs` に `AuthMethod` enum を作成
    - `AppSettings.cs` に `AuthMethod` / `AwsProfileName` プロパティを追加（JSON シリアライズ対応、デフォルト値 `"accessKey"` / `""`）
    - _Requirements: 3.1, 3.2, 3.4, 6.6_

  - [ ] 5.2 `AWSConfigParser` の実装
    - `Services/AWSConfigParser.cs` を新規作成
    - macOS 版と同一の解析ロジック（`ParseProfileNames(string content)` / `LoadProfileNames(string? path)`）
    - `DefaultConfigPath`: `%USERPROFILE%\.aws\config` を返す
    - _Requirements: 2.1, 2.2, 6.5, 7.1, 7.2, 7.3_

  - [ ]* 5.3 `AWSConfigParser` のユニットテスト（Windows）
    - macOS 版と同等のテストケースを C# で実装
    - _Requirements: 2.1, 2.2, 7.1, 7.2, 7.3_

- [ ] 6. Windows: プロファイルベース認証とクライアント統合
  - [ ] 6.1 `AWSClientFactory` の実装
    - `Services/AWSClientFactory.cs` を新規作成
    - `MakeCredentials(SettingsStore store)`: `authMethod` に応じて `BasicAWSCredentials`（accessKey）または `CredentialProfileStoreChain`（awsProfile）で認証情報を生成
    - `ResolveRegion(SettingsStore store)`: プロファイルの region を優先、未設定時は settings.json にフォールバック
    - _Requirements: 4.1, 4.2, 4.3, 6.4_

  - [ ] 6.2 既存サービスの認証情報生成を `AWSClientFactory` に統合
    - `Summarizer.cs`: `AmazonBedrockRuntimeClient` 生成を `AWSClientFactory.MakeCredentials()` に置換
    - `S3Service.cs`: コンストラクタを `AWSCredentials` ベースに変更、または `AWSClientFactory` 経由で生成
    - `TranscribeClient.cs`: `CreateTranscribeServiceClient` を `AWSClientFactory` 経由に変更
    - `RealtimeTranscribeClient.cs`: クライアント生成を `AWSClientFactory` 経由に変更
    - `TranslateService.cs`: クライアント生成を `AWSClientFactory` 経由に変更
    - _Requirements: 4.1, 4.2, 5.1, 5.2_

- [ ] 7. Windows: 設定ダイアログ UI の実装
  - [ ] 7.1 `MainPage.xaml.cs` の設定ダイアログ拡張
    - `OnSettingsClick` 内に認証方式 `RadioButtons`（Access Key / AWS Profile）を追加
    - `accessKey` 選択時: 既存の Access Key / Secret Key フィールドを表示
    - `awsProfile` 選択時: プロファイル選択 `ComboBox` + リフレッシュボタンを表示、Access Key フィールドを非表示
    - `~/.aws/config` 不存在時 / プロファイル未定義時のエラーメッセージ表示
    - 接続テストを `authMethod` に応じて分岐
    - 設定保存時に `authMethod` / `awsProfileName` を `settings.json` に永続化
    - _Requirements: 1.1, 1.2, 1.3, 2.3, 2.4, 2.5, 2.6, 5.1, 5.2, 5.3, 5.4, 5.5, 6.2, 6.6_

- [x] 8. チェックポイント - Windows 実装の検証
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

- [ ] 9. 最終統合と後方互換性の確認
  - [ ] 9.1 後方互換性テスト
    - `authMethod` フィールドなしの既存 `settings.json` をデシリアライズし、デフォルト値 `"accessKey"` が使用されることを確認（macOS / Windows 両方）
    - Access Key 方式の既存動作が変更されていないことを確認
    - _Requirements: 1.4, 3.4_

  - [ ] 9.2 settings.json スキーマの整合性確認
    - macOS / Windows 両方で `authMethod` / `awsProfileName` フィールド名が同一であることを確認
    - _Requirements: 6.6_

- [x] 10. 最終チェックポイント
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

## Notes

- `*` 付きのタスクはオプションであり、MVP では省略可能
- macOS を先行実装し、Windows に適用する順序で構成
- 各タスクは要件番号を参照しトレーサビリティを確保
- プロパティテストは SwiftCheck（macOS）を使用
- 既存の Access Key 方式は完全に維持（後方互換性）
