# 要件定義ドキュメント（Requirements Document）

## はじめに（Introduction）

本ドキュメントは、既存の macOS 音声文字起こし・要約アプリケーションにおける文字起こしエンジンの置き換えに関する要件を定義する。現在 Apple の SFSpeechRecognizer を使用している文字起こし機能を Amazon Transcribe に移行し、クラウドベースの音声認識を実現する。既存の `Transcribing` プロトコルを活用し、アプリケーション全体への影響を最小限に抑えつつ、Amazon Transcribe の機能を統合する。

## 用語集（Glossary）

- **App**: macOS 上で動作する音声文字起こし・要約アプリケーション本体
- **TranscribeClient**: Amazon Transcribe API と通信し、音声データを送信して文字起こし結果を受信するコンポーネント
- **AppSettingsStore**: 全設定を JSON ファイルに永続化するコンポーネント
- **AudioFile**: ユーザーが入力する音声ファイル（m4a, wav, mp3 などの形式）
- **Transcript**: 音声ファイルから生成された文字起こしテキスト
- **TranscriptionLanguage**: 文字起こしに使用する言語（日本語: ja-JP、英語: en-US）
- **TranscriptionJob**: Amazon Transcribe に送信される文字起こしジョブ
- **S3Bucket**: 音声ファイルのアップロード先となる Amazon S3 バケット

## 要件（Requirements）

### 要件 1: アプリ設定の管理（Application Settings Management）

**ユーザーストーリー:** ユーザーとして、AWS 認証情報やファイル保存先をアプリケーションに設定し、次回起動時にも復元されるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL AWS 認証情報（Access Key ID、Secret Access Key、リージョン）、S3 バケット名、録音データ保存先、エクスポートデータ保存先を入力するための設定画面を提供する
2. WHEN ユーザーが設定を保存した場合、THE App SHALL 全設定（AWS 認証情報、S3 バケット名、録音データ保存先、エクスポート保存先）を JSON ファイル（`~/Library/Application Support/AudioTranscriptionSummary/settings.json`）に保存する
3. WHEN App が起動した場合、THE App SHALL JSON ファイルから保存済みの設定を読み込む
4. IF 認証情報が未設定の状態で文字起こしが開始された場合、THEN THE App SHALL 「AWS 認証情報が設定されていません。設定画面から認証情報を入力してください」というメッセージを表示する
5. THE App SHALL 設定画面をシート（モーダル）として表示し、閉じるボタンで元の画面に戻れるようにする
6. WHEN ユーザーが認証情報の削除を要求した場合、THE App SHALL JSON ファイルから認証情報を完全に削除する
7. THE App SHALL 設定画面で AWS 接続テスト機能を提供し、S3 バケットへの書き込み・削除で認証情報の有効性を確認できるようにする
8. THE App SHALL リージョン選択をドロップダウン（Picker）で提供し、Amazon Transcribe 対応の主要リージョンから選択できるようにする

### 要件 2: Amazon Transcribe による文字起こし（Transcription with Amazon Transcribe）

**ユーザーストーリー:** ユーザーとして、Amazon Transcribe を使用して音声ファイルの文字起こしを行いたい。それにより、高精度なクラウドベースの音声認識を利用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが文字起こしボタンを押した場合、THE TranscribeClient SHALL Amazon Transcribe API を使用して AudioFile の文字起こしを開始する
2. THE TranscribeClient SHALL 既存の Transcribing プロトコルに準拠する
3. THE TranscribeClient SHALL 日本語（ja-JP）の音声を文字起こしする機能を提供する
4. THE TranscribeClient SHALL 英語（en-US）の音声を文字起こしする機能を提供する
5. WHILE 文字起こし処理が実行中の間、THE TranscribeClient SHALL 進捗状況を onProgress コールバックで通知する
6. WHEN 文字起こしが完了した場合、THE TranscribeClient SHALL 認識結果を Transcript モデルとして返す
7. IF AudioFile の音声が無音のみの場合、THEN THE TranscribeClient SHALL AppError.silentAudio エラーを返す
8. WHEN ユーザーがキャンセルを要求した場合、THE TranscribeClient SHALL 実行中の文字起こしジョブを中止する

### 要件 3: 音声ファイルの S3 アップロード（Audio File Upload to S3）

**ユーザーストーリー:** ユーザーとして、文字起こし処理が自動的に音声ファイルをクラウドにアップロードしてほしい。それにより、手動操作なしで Amazon Transcribe を利用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 文字起こしが開始された場合、THE TranscribeClient SHALL AudioFile を Amazon S3 バケットにアップロードする
2. WHEN アップロードが完了した場合、THE TranscribeClient SHALL S3 上のファイル URI を使用して TranscriptionJob を作成する
3. IF S3 へのアップロードに失敗した場合、THEN THE TranscribeClient SHALL アップロード失敗の原因を含む AppError.transcriptionFailed エラーを返す
4. WHEN 文字起こしが完了した場合、THE TranscribeClient SHALL S3 にアップロードした一時ファイルを削除する
5. THE TranscribeClient SHALL アップロードするファイル名に UUID を付与し、ファイル名の衝突を防止する

### 要件 4: エラーハンドリング（Error Handling）

**ユーザーストーリー:** ユーザーとして、Amazon Transcribe の利用中にエラーが発生した場合、原因がわかるメッセージを確認したい。それにより、問題を解決して再試行できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. IF AWS 認証情報が無効な場合、THEN THE TranscribeClient SHALL 「AWS 認証情報が無効です。設定画面で認証情報を確認してください」というエラーメッセージを含む AppError.transcriptionFailed を返す
2. IF ネットワーク接続が利用できない場合、THEN THE TranscribeClient SHALL 「ネットワーク接続を確認してください」というエラーメッセージを含む AppError.transcriptionFailed を返す
3. IF Amazon Transcribe のジョブが失敗した場合、THEN THE TranscribeClient SHALL ジョブの失敗理由を含む AppError.transcriptionFailed を返す
4. IF S3 バケットへのアクセス権限がない場合、THEN THE TranscribeClient SHALL 「S3 バケットへのアクセス権限がありません。IAM ポリシーを確認してください」というエラーメッセージを含む AppError.transcriptionFailed を返す
5. WHEN エラーが発生した場合、THE App SHALL 再試行ボタンを提供する

### 要件 5: 既存アーキテクチャとの統合（Integration with Existing Architecture）

**ユーザーストーリー:** 開発者として、Amazon Transcribe の統合が既存のアプリケーション構造を壊さないようにしたい。それにより、他の機能（要約、エクスポート、再生など）が引き続き正常に動作するようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE TranscribeClient SHALL 既存の Transcribing プロトコルの transcribe メソッドシグネチャに準拠する
2. THE TranscribeClient SHALL 既存の Transcribing プロトコルの cancel メソッドを実装する
3. WHEN TranscribeClient が AppViewModel に注入された場合、THE App SHALL 要約、エクスポート、再生の各機能を変更なしで利用できる
4. THE TranscribeClient SHALL 既存の TranscriptionLanguage 列挙型（japanese: "ja-JP"、english: "en-US"）を Amazon Transcribe の言語コードにマッピングする
5. THE TranscribeClient SHALL 既存の AppError 列挙型を使用してエラーを報告する

### 要件 6: AWS SDK の依存関係管理（AWS SDK Dependency Management）

**ユーザーストーリー:** 開発者として、AWS SDK for Swift をプロジェクトに適切に統合したい。それにより、Amazon Transcribe と S3 の API を利用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL Swift Package Manager を通じて AWS SDK for Swift（AWSTranscribe、AWSS3）を依存関係として追加する
2. THE App SHALL macOS 14（Sonoma）以降との互換性を維持する
3. THE App SHALL 既存の依存関係（SwiftCheck）との競合を発生させない

### 要件 7: UI 設計方針（UI Design Policy）

**ユーザーストーリー:** ユーザーとして、全機能を1画面で操作したい。それにより、画面遷移なしで効率的に作業できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL メイン画面を左右分割レイアウト（HSplitView）で構成し、左パネルに入力エリア（ファイル読み込み・キャプチャ・プレーヤー）、右パネルに出力エリア（文字起こし・要約）を配置する
2. THE App SHALL 設定画面以外で画面遷移を行わない
3. THE App SHALL 設定画面をシート（モーダル）として表示する
4. THE App SHALL 各セクションに統一されたヘッダー（アイコン + タイトル）を表示する
5. THE App SHALL エクスポート保存先が設定済みの場合、ダイアログなしで直接保存する。未設定の場合は NSSavePanel で保存先を選択する
6. THE App SHALL 「文字起こし＋要約」ボタン1つで文字起こし→要約→自動エクスポートを一括実行する

### 要件 8: ファイル命名規則（File Naming Convention）

**ユーザーストーリー:** ユーザーとして、生成されるファイルの名前が日時ベースで統一されていてほしい。それにより、ファイルの整理と検索が容易になるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL すべての生成ファイルの名前に日時（`yyyyMMdd_HHmmss` 形式）を使用する
2. THE SystemAudioCapture SHALL 録音ファイルを `system_audio_yyyyMMdd_HHmmss.mp3` として保存する
3. THE ScreenRecorder SHALL 画面録画ファイルを `screen_recording_yyyyMMdd_HHmmss.mp4` として保存する
4. THE ScreenRecorder SHALL 画面録画と同時に音声ファイルを `screen_audio_yyyyMMdd_HHmmss.mp3` として別途保存する
5. THE App SHALL 文字起こし結果を `transcript_yyyyMMdd_HHmmss.txt` として保存する
6. THE App SHALL 要約結果を `summary_yyyyMMdd_HHmmss.txt` として保存する
7. THE App SHALL 文字起こし結果と要約結果を別ファイルに分離して保存する

### 要件 9: 録画・録音形式（Recording Format）

**ユーザーストーリー:** ユーザーとして、録画・録音データを汎用的な形式で保存したい。それにより、他のアプリケーションでも再生・編集できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE ScreenRecorder SHALL 画面録画を MP4 形式（H.264 + AAC）で保存する
2. THE ScreenRecorder SHALL 画面録画と同時に音声のみのファイルを MP3 形式で別途保存する
3. THE SystemAudioCapture SHALL システム音声を MP3 形式で保存する
4. THE App SHALL 音声キャプチャのサンプルレートを 48kHz、チャンネル数を 2（ステレオ）に設定する
5. THE SystemAudioCapture SHALL 録音中は音声をパススルー（変換なし）で一時 MOV ファイルに保存し、停止後に AVAssetExportSession で MP3 に変換する
6. THE ScreenRecorder SHALL 録画中は音声をパススルーで一時 MOV ファイルに保存し、停止後に MP3 に変換する
7. IF 画面収録の権限が付与されていない場合、THEN THE App SHALL 「システム設定 > プライバシーとセキュリティ > 画面収録とシステム音声」への案内メッセージを表示する

### 要件 10: CPU・メモリ使用状況の表示（System Resource Monitoring）

**ユーザーストーリー:** ユーザーとして、アプリケーション使用中にシステムの CPU・メモリ使用状況を確認したい。それにより、リソース消費を把握しながら作業できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL メインウィンドウ下部にステータスバーを表示する
2. THE StatusBarView SHALL CPU 使用率をリアルタイムで表示する
3. THE StatusBarView SHALL メモリ使用量をリアルタイムで表示する
4. THE StatusBarView SHALL 定期的にシステムリソース情報を更新する

### 要件 11: 音源リソースの選択（Audio Source Selection）

**ユーザーストーリー:** ユーザーとして、録音時にシステム音声・マイク・特定アプリケーションの音声から音源を選択したい。それにより、目的に応じた音声を録音できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 録音開始前に音源リソースを選択するドロップダウン（Picker）を提供する
2. THE App SHALL 以下の音源種別を選択肢として提供する:
   - システム全体の音声（ScreenCaptureKit 使用）
   - マイク入力（AVCaptureSession 使用、内蔵マイク・外部マイクを含む）
   - 特定アプリケーションの音声（ScreenCaptureKit の SCContentFilter 使用）
3. THE App SHALL 画面表示時に利用可能な音源リソース一覧を自動取得する
4. WHEN マイクが選択された場合、THE SystemAudioCapture SHALL AVCaptureSession を使用してマイク音声をキャプチャする
5. WHEN システム音声またはアプリケーションが選択された場合、THE SystemAudioCapture SHALL ScreenCaptureKit を使用して音声をキャプチャする
6. THE App SHALL マイクデバイスの一覧を AVCaptureDevice.DiscoverySession から取得する
7. WHEN ユーザーが録音停止ボタンを押した場合、THE App SHALL 録音ファイルを保存先に保存し、音声プレーヤーに読み込む（文字起こしは自動実行しない）
8. THE App SHALL 録音停止後、ユーザーが右パネルの「文字起こし＋要約」ボタンで明示的に文字起こしを開始できるようにする
