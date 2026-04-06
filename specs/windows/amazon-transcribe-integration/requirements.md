# 要件定義ドキュメント（Requirements Document）- Windows版

## はじめに（Introduction）

本ドキュメントは、Windows版音声文字起こし・要約アプリケーション（WinUI 3 / .NET 8）におけるAmazon Transcribe連携の要件を定義する。AWS SDK for .NETを使用してAmazon TranscribeとS3の機能を統合し、クラウドベースの音声認識を実現する。

## 用語集（Glossary）

- **App**: Windows版AudioTranscriptionSummaryアプリケーション（WinUI 3 / .NET 8）
- **TranscribeClient**: Amazon Transcribe APIと通信し、文字起こしジョブを管理するコンポーネント
- **SettingsStore**: 全設定をJSONファイルに永続化するコンポーネント（%APPDATA%\AudioTranscriptionSummary\settings.json）
- **AudioFile**: ユーザーが入力する音声ファイル
- **Transcript**: 音声から生成された文字起こしテキスト
- **TranscriptionJob**: Amazon Transcribeに送信される文字起こしジョブ
- **S3Bucket**: 音声ファイルのアップロード先となるAmazon S3バケット

## 要件（Requirements）

### 要件 1: アプリ設定の管理（Application Settings Management）

**ユーザーストーリー:** ユーザーとして、AWS認証情報やファイル保存先をアプリケーションに設定し、次回起動時にも復元されるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL AWS認証情報（Access Key ID、Secret Access Key、リージョン）、S3バケット名、録音データ保存先、エクスポートデータ保存先を入力するためのContentDialogベースの設定画面を提供する（MinWidth=750）
2. WHEN ユーザーが設定を保存した場合、THE App SHALL 全設定をJSONファイル（%APPDATA%\AudioTranscriptionSummary\settings.json）に保存する
3. WHEN Appが起動した場合、THE App SHALL JSONファイルから保存済みの設定を読み込む
4. IF 認証情報が未設定の状態で文字起こしが開始された場合、THEN THE App SHALL ContentDialogで「AWS認証情報が設定されていません」というメッセージを表示する
5. WHEN ユーザーが認証情報の削除を要求した場合、THE App SHALL JSONファイルから認証情報を削除する
6. THE App SHALL 設定画面でAWS接続テスト機能を提供し、S3バケットへの書き込み・削除で認証情報の有効性を確認できるようにする。テスト中はProgressRingを表示し、結果を色付きステータスバッジで表示する
7. THE App SHALL リージョン選択をComboBoxで提供し、Amazon Transcribe対応の主要リージョンから選択できるようにする
8. THE App SHALL 接続ステータスバッジを表示する（灰色「未設定」、黄色「未検証」、緑「接続成功」、赤「接続失敗」）
9. THE App SHALL 設定画面のグループラベルに青色バッジを使用する（🔑 AWS認証情報、📁 フォルダ設定、🎙️ リアルタイム設定、🔍 要約（Bedrock））
10. THE App SHALL フォルダ選択ボタンを別行に配置する（「📁 フォルダを選択...」）
11. THE App SHALL 設定画面に「🔍 要約（Bedrock）」グループを表示し、基盤モデル選択ComboBoxを提供する
12. WHEN ユーザーがリージョンを変更した場合、THE App SHALL 利用可能なBedrockモデルリストを自動更新する

### 要件 2: Amazon Transcribeによる文字起こし（Transcription with Amazon Transcribe）

**ユーザーストーリー:** ユーザーとして、Amazon Transcribeを使用して音声ファイルの文字起こしを行いたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが文字起こしボタンを押した場合、THE TranscribeClient SHALL AWS SDK for .NETのAWSSDK.TranscribeServiceを使用して文字起こしを開始する
2. THE TranscribeClient SHALL 日本語（ja-JP）・英語（en-US）を含む21言語の音声を文字起こしする機能を提供する
3. WHILE 文字起こし処理が実行中の間、THE TranscribeClient SHALL ProgressBarで進捗状況を通知する（0.1検証→0.2アップロード→0.4ジョブ作成→0.4-0.8ポーリング→0.9クリーンアップ→1.0完了）
4. WHEN 文字起こしが完了した場合、THE TranscribeClient SHALL 認識結果をTranscriptモデルとして返す
5. IF AudioFileの音声が無音のみの場合、THEN THE TranscribeClient SHALL 無音エラーを返す
6. WHEN 「自動判別」言語が選択された場合、THE TranscribeClient SHALL `IdentifyLanguage=true` を使用して言語を自動判別する

### 要件 3: Bedrock Cross-Region推論プロファイル（Bedrock Cross-Region Inference Profile）

**ユーザーストーリー:** ユーザーとして、どのリージョンでもBedrock要約が正しく動作してほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Summarizer SHALL `BedrockModel.GetInferenceId(region)` を使用してCross-Region inference profile IDを取得し、Bedrock APIに送信する
2. THE BedrockModel SHALL リージョンに応じて適切なinference ID（us.*, eu.*, global.*）を返す
3. THE Summarizer SHALL 生のモデルIDではなくinference profile IDを使用することで、on-demand throughputのValidationExceptionを回避する

### 要件 4: 音声ファイルのS3アップロード（Audio File Upload to S3）

**ユーザーストーリー:** ユーザーとして、文字起こし処理が自動的に音声ファイルをクラウドにアップロードしてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 文字起こしが開始された場合、THE TranscribeClient SHALL AWSSDK.S3を使用してAudioFileをS3バケットにアップロードする
2. THE TranscribeClient SHALL UUID付きファイル名（{UUID}.{extension}）でアップロードする
3. IF S3へのアップロードに失敗した場合、THEN THE TranscribeClient SHALL 原因を含むエラーを返す
4. WHEN 文字起こしが完了した場合、THE TranscribeClient SHALL S3の一時ファイルを削除する（ベストエフォート）

### 要件 5: エラーハンドリング（Error Handling）

**ユーザーストーリー:** ユーザーとして、Amazon Transcribeの利用中にエラーが発生した場合、原因がわかるメッセージを確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. IF AWS認証情報が無効な場合、THEN THE TranscribeClient SHALL 「AWS認証情報が無効です。設定画面で確認してください」というエラーを返す
2. IF ネットワーク接続が利用できない場合、THEN THE TranscribeClient SHALL 「ネットワーク接続を確認してください」というエラーを返す
3. IF Transcribeジョブが失敗した場合、THEN THE TranscribeClient SHALL ジョブの失敗理由を含むエラーを返す
4. IF S3バケットへのアクセス権限がない場合、THEN THE TranscribeClient SHALL 「IAMポリシーを確認してください」というエラーを返す
5. WHEN エラーが発生した場合、THE App SHALL ContentDialogで再試行ボタンを提供する

### 要件 6: UI設計方針（UI Design Policy）

**ユーザーストーリー:** ユーザーとして、全機能を1画面で操作したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 上下分割レイアウトを採用する（上部: 入力、下部: 出力）
2. THE App SHALL 設定画面以外で画面遷移を行わない
3. THE App SHALL 設定画面をContentDialogとして表示する
4. THE App SHALL 各セクションにWinUI 3 Expanderを使用する
5. THE App SHALL エクスポート保存先が設定済みの場合は文字起こし＋要約完了後に自動エクスポートする（CommandBarにエクスポートボタンは配置しない）
6. THE App SHALL 「文字起こし＋要約」ボタン1つで一括実行する

### 要件 7: AWS SDK依存関係管理（AWS SDK Dependency Management）

**ユーザーストーリー:** 開発者として、AWS SDK for .NETをプロジェクトに適切に統合したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL NuGetを通じてAWSSDK.TranscribeService 4.*、AWSSDK.S3 4.* を依存関係として使用する
2. THE App SHALL .NET 8およびWindows 10 19041以降との互換性を維持する
3. THE App SHALL 既存の依存関係（CommunityToolkit.Mvvm、NAudio）との競合を発生させない
