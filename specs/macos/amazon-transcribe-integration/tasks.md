# 実装計画: Amazon Transcribe 統合（Amazon Transcribe Integration）

## 概要

既存の macOS 音声文字起こしアプリケーションに Amazon Transcribe を統合する。AWS SDK for Swift の依存追加、認証情報管理（Keychain）、S3 アップロード、TranscribeClient の実装、設定画面の追加を段階的に進める。既存の `Transcribing` プロトコルへの準拠により、ViewModel 層以上の変更を最小限に抑える。

## タスク

- [x] 1. AWS SDK 依存関係の追加とデータモデルの作成
  - [x] 1.1 Package.swift に AWS SDK for Swift（AWSTranscribe, AWSS3）の依存関係を追加する
    - `.package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0")` を追加
    - ターゲットに `AWSTranscribe`, `AWSS3` の product 依存を追加
    - 既存の SwiftCheck 依存との競合がないことを確認
    - macOS 14（Sonoma）のデプロイメントターゲットを維持
    - _要件: 6.1, 6.2, 6.3_

  - [x] 1.2 AWSCredentials 構造体と AWSCredentialManaging プロトコルを作成する
    - `Models/AWSCredentials.swift` に `AWSCredentials` 構造体を定義（accessKeyId, secretAccessKey, region, isValid）
    - `Services/Services.swift` に `AWSCredentialManaging` プロトコルを追加（loadCredentials, saveCredentials, deleteCredentials, hasCredentials）
    - _要件: 1.2, 1.3, 1.6_

  - [x] 1.3 TranscribeJobConfig 構造体と AWS サービス抽象化プロトコルを作成する
    - `Models/TranscribeJobConfig.swift` に `TranscribeJobConfig` 構造体を定義（jobName, mediaFileUri, languageCode, outputBucketName）
    - `Services/Services.swift` に `S3ClientProtocol` と `TranscribeClientProtocol` を追加
    - `TranscriptionJobStatus` 列挙型を定義（inProgress, completed, failed）
    - _要件: 3.2, 3.5_


- [x] 2. AWSCredentialManager の実装
  - [x] 2.1 AWSCredentialManager を実装する
    - `Services/AWSCredentialManager.swift` を作成
    - macOS Keychain（Security フレームワーク）を使用した認証情報の保存・読み込み・削除
    - サービス名: `com.app.AudioTranscriptionSummary.aws`
    - `kSecClassGenericPassword` + `kSecAttrAccount` でフィールドを区別
    - 平文でのファイルシステム保存を行わない
    - _要件: 1.2, 1.3, 1.5, 1.6_

  - [x]* 2.2 Property 1 のプロパティベーステストを作成する
    - **Property 1: 認証情報のラウンドトリップ（Credentials Round Trip）**
    - ランダムな英数字文字列で AWSCredentials を生成し、保存→読み込みで同一の値が返ることを検証
    - // Feature: amazon-transcribe-integration, Property 1: 認証情報のラウンドトリップ
    - **検証対象: 要件 1.2, 1.3**

  - [x]* 2.3 Property 2 のプロパティベーステストを作成する
    - **Property 2: 認証情報の削除完全性（Credentials Deletion Completeness）**
    - ランダムな AWSCredentials を保存→削除し、loadCredentials() が nil、hasCredentials が false を返すことを検証
    - // Feature: amazon-transcribe-integration, Property 2: 認証情報の削除完全性
    - **検証対象: 要件 1.6**

  - [x]* 2.4 AWSCredentialManager のユニットテストを作成する
    - 認証情報の保存・読み込み成功テスト
    - 認証情報の削除成功テスト
    - 未設定時に nil が返ることのテスト
    - _要件: 1.2, 1.3, 1.6_


- [x] 3. TranscribeClient の実装
  - [x] 3.1 S3 アップロード・削除機能を実装する
    - `Services/AWSS3Service.swift` を作成（S3ClientProtocol の実装）
    - AWSS3.S3Client を使用した putObject / deleteObject
    - UUID ベースのファイル名生成（`{UUID}.{拡張子}` 形式）
    - _要件: 3.1, 3.4, 3.5_

  - [x] 3.2 TranscribeClient を実装する
    - `Services/TranscribeClient.swift` を作成
    - `Transcribing` プロトコルに準拠
    - 認証情報の検証 → S3 アップロード → ジョブ作成 → ポーリング → 結果取得 → クリーンアップの処理フロー
    - 3 秒間隔のポーリングによるジョブステータス確認
    - 結果 JSON からテキスト抽出
    - onProgress コールバックによる進捗通知（0.0〜1.0）
    - cancel() によるジョブ中止機能
    - _要件: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8_

  - [x] 3.3 エラーハンドリングを実装する
    - AWS SDK エラーから AppError へのマッピングロジック
    - 認証情報未設定/無効、ネットワークエラー、S3 アクセス拒否、ジョブ失敗の各ケース
    - 無音検出時の silentAudio エラー
    - エラー時の S3 一時ファイル削除（ベストエフォート）
    - _要件: 1.4, 4.1, 4.2, 4.3, 4.4_


  - [x]* 3.4 Property 3 のプロパティベーステストを作成する
    - **Property 3: 進捗値の範囲整合性（Progress Value Range Consistency）**
    - モックの TranscribeClientProtocol を使用し、任意の文字起こし処理で onProgress の値が 0.0〜1.0 の範囲内であることを検証
    - // Feature: amazon-transcribe-integration, Property 3: 進捗値の範囲整合性
    - **検証対象: 要件 2.5**

  - [x]* 3.5 Property 4 のプロパティベーステストを作成する
    - **Property 4: Transcript モデルの整合性（Transcript Model Consistency）**
    - モックを使用し、成功した文字起こしの Transcript が正しい audioFileId、language、非空テキストを持つことを検証
    - // Feature: amazon-transcribe-integration, Property 4: Transcript モデルの整合性
    - **検証対象: 要件 2.6**

  - [x]* 3.6 Property 5 のプロパティベーステストを作成する
    - **Property 5: S3 キーの一意性と URI 形式（S3 Key Uniqueness and URI Format）**
    - ランダムな AudioFile とバケット名で S3 キーを生成し、UUID を含む正しい URI 形式であること、複数回生成で重複しないことを検証
    - // Feature: amazon-transcribe-integration, Property 5: S3 キーの一意性と URI 形式
    - **検証対象: 要件 3.2, 3.5**

  - [x]* 3.7 TranscribeClient のユニットテストを作成する
    - 認証情報未設定時のエラーテスト
    - 認証情報無効時のエラーメッセージテスト
    - ネットワークエラー時のエラーメッセージテスト
    - ジョブ失敗時のエラーメッセージテスト
    - S3 アクセス拒否時のエラーメッセージテスト
    - 無音検出時の silentAudio エラーテスト
    - キャンセル処理テスト
    - S3 一時ファイル削除確認テスト
    - 言語コードマッピングテスト（ja-JP, en-US）
    - _要件: 1.4, 2.7, 2.8, 3.4, 4.1, 4.2, 4.3, 4.4, 5.4_


- [x] 4. チェックポイント - 認証情報管理と TranscribeClient の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問する。

- [x] 5. AWS 設定画面と AppViewModel 統合
  - [x] 5.1 AWSSettingsViewModel を実装する
    - `ViewModels/AWSSettingsViewModel.swift` を作成
    - 認証情報の入力・保存・削除・読み込み機能
    - バリデーション（空文字チェック）とエラーメッセージ表示
    - _要件: 1.1, 1.2, 1.6_

  - [x] 5.2 AWSSettingsView を実装する
    - `Views/AWSSettingsView.swift` を作成
    - Access Key ID 入力フィールド
    - Secret Access Key 入力フィールド（SecureField）
    - リージョン選択
    - S3 バケット名入力フィールド
    - 保存ボタン / 削除ボタン
    - 保存成功/エラーのフィードバック表示
    - _要件: 1.1_

  - [x] 5.3 AppViewModel と MainView に TranscribeClient を統合する
    - アプリケーション起動時に AWSCredentialManager から認証情報を読み込み
    - 認証情報が設定済みの場合、TranscribeClient を AppViewModel に注入
    - MainView に AWS 設定画面へのナビゲーションを追加
    - 再試行ボタンの動作確認
    - _要件: 4.5, 5.3_

  - [x]* 5.4 統合テストを作成する
    - TranscribeClient を注入した AppViewModel で要約・エクスポート・再生が正常動作することを検証
    - _要件: 5.3_

- [x] 6. 最終チェックポイント - 全体の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問する。

- [x] 7. 設定画面の改善と録音データ保存先の追加
  - [x] 7.1 AWSSettingsViewModel に録音データ保存先管理機能を追加する
    - `recordingDirectoryPath` プロパティ（UserDefaults 永続化）
    - `chooseRecordingDirectory()`: NSOpenPanel でフォルダ選択
    - `resetRecordingDirectory()`: デフォルト（一時ディレクトリ）にリセット
    - `static var recordingDirectory: URL`: 保存先ディレクトリの取得
    - S3 バケット名の UserDefaults 永続化
    - _要件: 追加機能_

  - [x] 7.2 AWSSettingsView を統合設定画面に改善する
    - 「録音データ保存先」セクション追加（フォルダ選択・リセット）
    - リージョン選択を Picker（ドロップダウン）に変更（主要12リージョン）
    - 「接続テスト」ボタン追加（S3 書き込み・削除で検証）
    - 接続ステータスバッジ（未設定/未検証/テスト中/接続済み）
    - LabeledContent + SF Symbols による UI 改善
    - _要件: 追加機能_

  - [x] 7.3 SystemAudioCapture と ScreenRecorder の保存先を設定参照に変更する
    - `FileManager.default.temporaryDirectory` → `AWSSettingsViewModel.recordingDirectory`
    - _要件: 追加機能_

  - [x] 7.4 MainView のツールバーボタンを「設定」に統合する
    - アイコンを cloud → gearshape に変更
    - ラベルを「AWS 設定」→「設定」に変更
    - _要件: 追加機能_

- [x] 8. JSON 設定ファイルへの移行と1画面レイアウト
  - [x] 8.1 AppSettingsStore を作成し、全設定を JSON ファイルに永続化する
    - `Services/AppSettingsStore.swift` を作成
    - `~/Library/Application Support/AudioTranscriptionSummary/settings.json` に保存
    - AWS 認証情報（accessKeyId, secretAccessKey）も JSON に含める
    - Keychain / UserDefaults は不使用
    - _要件: 1.2, 1.3_

  - [x] 8.2 AWSSettingsViewModel を JSON ベースに書き換える
    - Keychain 依存を完全に除去
    - 全設定の読み込み・保存を AppSettingsStore 経由に統一
    - JSONCredentialManager を作成し AWSCredentialManaging プロトコルに準拠
    - _要件: 1.2, 1.3, 1.6_

  - [x] 8.3 MainView を1画面レイアウト（HSplitView）に書き換える
    - 左パネル: 入力エリア（ファイル読み込み + キャプチャ + プレーヤー）
    - 右パネル: 出力エリア（文字起こし + 要約、VSplitView）
    - 統一セクションヘッダー（アイコン + タイトル）
    - 設定以外の画面遷移を廃止
    - エクスポート保存先設定済みの場合はダイアログなしで直接保存
    - _要件: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [x] 8.4 要件・設計ドキュメントを更新する
    - requirements.md: 要件1を JSON 保存に変更、要件7（UI 設計方針）を追加
    - design.md: Keychain → JSON、アーキテクチャ図更新、1画面レイアウト記載
    - _要件: ドキュメント更新_

- [x] 9. 録画形式の MP4 化と音声同時保存
  - [x] 9.1 ScreenRecorder を MP4 形式に変更し、音声ファイルを同時保存する
    - 動画: MP4（H.264 + AAC, 48kHz, ステレオ）
    - 音声: 別ファイルで MP4（AAC）として同時保存
    - AppViewModel の stopScreenRecording から音声抽出ステップを削除
    - _要件: 9.1, 9.2, 9.4_

  - [x] 9.2 SystemAudioCapture を MP4 形式に変更する
    - 出力形式: MP4（AAC, 48kHz, ステレオ）
    - セッション開始を最初のサンプルのタイムスタンプで実行
    - 音声レベル計算を Float32 フォーマットに対応
    - _要件: 9.3, 9.4_

- [x] 10. 文字起こし＋要約の一括実行と自動エクスポート
  - [x] 10.1 AppViewModel に transcribeAndSummarize メソッドを追加する
    - 文字起こし → 要約 → 自動エクスポートを一括実行
    - エクスポート先設定済みの場合、文字起こしと要約を別ファイルに保存
    - _要件: 7.6, 8.5, 8.6, 8.7_

  - [x] 10.2 TranscriptView を統合ボタンに変更する
    - 「文字起こし＋要約」ボタン1つに統合
    - 文字起こし中・要約中のプログレス表示
    - _要件: 7.6_

  - [x] 10.3 SummaryView を結果表示のみに簡素化する
    - 要約ボタンを削除、結果表示のみ
    - _要件: 7.6_

- [x] 11. ファイル名の日時ベース統一
  - [x] 11.1 全生成ファイルのファイル名を yyyyMMdd_HHmmss 形式に変更する
    - SystemAudioCapture: system_audio_yyyyMMdd_HHmmss.mp4
    - ScreenRecorder: screen_recording_yyyyMMdd_HHmmss.mp4 + screen_audio_yyyyMMdd_HHmmss.mp4
    - エクスポート: transcript_yyyyMMdd_HHmmss.txt + summary_yyyyMMdd_HHmmss.txt
    - _要件: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x] 11.2 要件・設計ドキュメントを更新する
    - requirements.md: 要件8（ファイル命名規則）、要件9（録画形式）を追加
    - design.md: ファイル命名規則セクション、一括処理フロー図を追加
    - _要件: ドキュメント更新_

- [x] 12. 録音方式の修正と M4A 出力
  - [x] 12.1 SystemAudioCapture をパススルー + 後変換方式に修正する
    - 録音中: パススルー（outputSettings: nil）で一時 MOV に書き込み
    - 停止後: AVAssetExportSession（AppleM4A プリセット）で M4A に変換
    - 一時 MOV ファイルを自動削除
    - 出力: system_audio_yyyyMMdd_HHmmss.m4a
    - _要件: 9.3, 9.5_

  - [x] 12.2 ScreenRecorder をパススルー + 後変換方式に修正する
    - 動画: H.264 映像 + パススルー音声で一時 MOV → AVAssetExportSession で MP4 に変換
    - 音声: パススルーで一時 MOV → AVAssetExportSession で M4A に変換
    - 出力: screen_recording_yyyyMMdd_HHmmss.mp4 + screen_audio_yyyyMMdd_HHmmss.m4a
    - _要件: 9.1, 9.2, 9.6_

  - [x] 12.3 権限チェックとエラーメッセージを改善する
    - ScreenCaptureKit の権限エラーをキャッチし、設定画面への案内メッセージを表示
    - _要件: 9.7_

  - [x] 12.4 仕様ドキュメントを更新する
    - requirements.md: 要件9にパススルー方式と権限チェックを追加
    - design.md: 録音方式セクション、ファイル形式を M4A に更新
    - _要件: ドキュメント更新_

- [x] 13. 音声出力形式の MP3 化
  - [x] 13.1 SystemAudioCapture の出力形式を M4A から MP3 に変更する
    - 停止後の変換: MOV → MP3（AVAssetExportSession または AVAssetReader + AVAssetWriter で MP3 エンコード）
    - 出力ファイル名: `system_audio_yyyyMMdd_HHmmss.mp3`
    - AudioFile の fileExtension を `mp3` に変更
    - _要件: 8.2, 9.3, 9.5_

  - [x] 13.2 ScreenRecorder の音声出力形式を M4A から MP3 に変更する
    - 音声の停止後変換: MOV → MP3
    - 動画は MP4（H.264 + AAC）のまま維持
    - 出力ファイル名: `screen_audio_yyyyMMdd_HHmmss.mp3`
    - AudioFile の fileExtension を `mp3` に変更
    - _要件: 8.4, 9.2, 9.6_

  - [x] 13.3 design.md の録音方式セクションを MP3 変換に更新する
    - パススルー + 後変換の説明を MP3 に修正
    - _要件: ドキュメント更新_

  - [x] 13.4 動作確認
    - SystemAudioCapture で MP3 ファイルが正常に生成されることを確認
    - ScreenRecorder で MP4（動画）+ MP3（音声）が正常に生成されることを確認
    - 生成された MP3 ファイルで文字起こしが正常に動作することを確認

- [x] 14. 音源リソースの選択機能
  - [x] 14.1 AudioSourceType モデルと AudioSourceProvider を作成する
    - `Models/AudioSource.swift` を作成
    - AudioSourceType 列挙型: systemAudio, microphone(deviceID, name), application(bundleID, name)
    - AudioSourceProvider: AVCaptureDevice.DiscoverySession + SCShareableContent から音源一覧を取得
    - _要件: 11.2, 11.3, 11.6_

  - [x] 14.2 SystemAudioCapture にマイク録音対応を追加する
    - startCapture(sourceType:) にマイク分岐を追加
    - マイク: AVCaptureSession + AVCaptureDeviceInput で録音
    - システム音声/アプリ: 従来の ScreenCaptureKit を使用
    - AVCaptureAudioDataOutputSampleBufferDelegate でサンプルバッファを受信
    - _要件: 11.4, 11.5_

  - [x] 14.3 AppViewModel に音源選択プロパティを追加する
    - selectedAudioSource: AudioSourceType（デフォルト: systemAudio）
    - availableAudioSources: [AudioSourceType]
    - refreshAudioSources(): 利用可能な音源を更新
    - startSystemAudioCapture() で selectedAudioSource を使用
    - _要件: 11.1, 11.3_

  - [x] 14.4 SystemAudioCaptureView に音源選択 Picker を追加する
    - 録音開始前に音源ドロップダウンを表示
    - .task で画面表示時に音源一覧を自動取得
    - _要件: 11.1_

  - [x] 14.5 仕様・設計ドキュメントを更新する
    - requirements.md: 要件11（音源リソースの選択）を追加
    - design.md: 音源選択セクション、録音方式の分岐テーブルを追加
    - _要件: ドキュメント更新_

- [x] 15. 録音停止を「保存のみ」に変更
  - [x] 15.1 SystemAudioCaptureView の停止ボタンラベルを変更する
    - 「停止して文字起こし」→「停止して保存」に変更
    - _要件: 11.7_

  - [x] 15.2 AppViewModel の stopSystemAudioCapture / stopScreenRecording を保存のみに変更する
    - 録音停止後は audioFile に読み込むのみ（文字起こしは自動実行しない）
    - 既存の動作は変更なし（audioFile 設定 + プレーヤー読み込み）
    - _要件: 11.7, 11.8_

  - [x] 15.3 仕様・設計ドキュメントを更新する
    - requirements.md: 要件11に停止後の動作を追加
    - design.md: 録音停止後の動作セクションを追加
    - _要件: ドキュメント更新_

- [x] 16. StatusBarView の実装
  - [x] 16.1 StatusBarView を実装する
    - `Views/StatusBarView.swift` を作成
    - Darwin フレームワークを使用した CPU 使用率・メモリ使用量の取得
    - タイマーによる定期更新
    - メインウィンドウ下部にステータスバーとして配置
    - _要件: 10.1, 10.2, 10.3, 10.4_

## 備考

- `*` マーク付きのタスクはオプションであり、MVP を優先する場合はスキップ可能
- 各タスクは対応する要件番号を参照しており、トレーサビリティを確保
- チェックポイントで段階的に動作を検証する
- AWS SDK への依存はプロトコル抽象化（S3ClientProtocol, TranscribeClientProtocol）により分離し、テスト時はモックを使用する
- プロパティベーステストは SwiftCheck を使用し、各テスト最低 100 回実行する
