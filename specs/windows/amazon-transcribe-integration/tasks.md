# 実装計画: Amazon Transcribe統合（Windows版）

## 概要

AWS SDK for .NET（AWSSDK.TranscribeService, AWSSDK.S3）を使用してAmazon Transcribeバッチ文字起こしを実装する。設定JSON永続化、S3アップロード、TranscribeClient、設定ダイアログを段階的に構築する。

## タスク

- [x] 1. TranscribeClient の実装
  - [x] 1.1 S3アップロード・削除機能を実装する
    - AmazonS3Client.PutObjectAsync / DeleteObjectAsync
    - UUID付きファイル名: {UUID}.{extension}
    - _要件: 3.1, 3.2, 3.3, 3.4_

  - [x] 1.2 TranscribeClient を実装する
    - 認証情報検証 → S3アップロード → StartTranscriptionJobAsync → ポーリング → 結果取得 → クリーンアップ
    - 3秒間隔ポーリング
    - IProgress<double> で進捗通知（0.1→0.2→0.4→0.4-0.8→0.9→1.0）
    - CancellationToken対応
    - _要件: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 1.3 エラーハンドリングを実装する
    - AmazonServiceException → AppError マッピング
    - 認証情報未設定/無効、ネットワーク、S3アクセス拒否、ジョブ失敗
    - 無音検出（結果テキスト空）→ SilentAudio
    - S3クリーンアップ（ベストエフォート）
    - _要件: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 2. 設定ダイアログの完全実装
  - [x] 2.1 SettingsDialog（ContentDialog）を完全実装する
    - AWS認証情報入力（TextBox, PasswordBox, ComboBox, TextBox）
    - フォルダ選択（FolderPicker）: 録音保存先、エクスポート保存先
    - リアルタイム設定（ToggleSwitch x2, ComboBox）
    - 保存/接続テスト/削除ボタン
    - 接続ステータスバッジ（灰/黄/緑）
    - バリデーション（空文字チェック）
    - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8_

  - [x] 2.2 接続テスト機能を実装する
    - S3にテストオブジェクト書き込み→削除
    - ProgressRing表示中はボタン無効化
    - 成功: 緑「接続成功」、失敗: エラーメッセージ
    - _要件: 1.6, 1.7, 1.8_

- [x] 3. MainViewModel にTranscribeClient を統合する
  - [x] 3.1 TranscribeAndSummarize を実装する
    - 認証情報検証 → TranscribeClient.TranscribeAsync → Summarizer.Summarize → 自動エクスポート
    - ProgressBar更新
    - エラー時ContentDialog + 再試行
    - _要件: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

- [x] 4. チェックポイント - Transcribe統合の動作確認

## 備考

- AWS SDKパッケージ（AWSSDK.TranscribeService, AWSSDK.S3）は既にcsprojに追加済み
- 各タスクは対応する要件番号を参照
