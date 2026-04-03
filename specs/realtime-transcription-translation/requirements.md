# 要件定義ドキュメント（Requirements Document）

## はじめに（Introduction）

本ドキュメントは、既存の macOS 音声文字起こし・要約アプリケーションに、Amazon Transcribe Streaming によるリアルタイム文字起こしと Amazon Translate によるリアルタイム翻訳機能を追加するための要件を定義する。現在のバッチ処理方式（録音完了後に S3 アップロード → Transcribe ジョブ実行）に加え、録音中にストリーミング方式で音声を直接 Amazon Transcribe Streaming API に送信し、リアルタイムで文字起こし結果をプレビュー表示する。さらに、文字起こし結果を Amazon Translate でリアルタイムに多言語翻訳し、翻訳結果を表示する機能を提供する。

## 用語集（Glossary）

- **App**: macOS 上で動作する音声文字起こし・要約アプリケーション本体
- **TranscribeStreamingClient**: Amazon Transcribe Streaming API と通信し、音声ストリームをリアルタイムで送信して文字起こし結果を受信するコンポーネント
- **TranslateClient**: Amazon Translate API と通信し、テキストをリアルタイムで翻訳するコンポーネント
- **SystemAudioCapture**: ScreenCaptureKit / AVCaptureSession でシステム音声・マイクをキャプチャするコンポーネント（既存）
- **RealtimeTranscriptionViewModel**: リアルタイム文字起こし・翻訳の状態管理を担当する ViewModel
- **TranscriptionPreviewPanel**: 録音中にリアルタイム文字起こし結果を表示する UI パネル
- **TranslationPanel**: 翻訳結果を表示する UI パネル
- **PartialTranscript**: Transcribe Streaming から返される暫定的な文字起こし結果（確定前のテキスト）
- **FinalTranscript**: Transcribe Streaming から返される確定済みの文字起こし結果
- **TranslationLanguage**: 翻訳先の言語（日本語、英語、中国語、韓国語、フランス語、ドイツ語、スペイン語）
- **AudioStream**: SystemAudioCapture から取得した音声データのストリーム（PCM バッファ）
- **AppSettingsStore**: 全設定を JSON ファイルに永続化するコンポーネント（既存）

## 要件（Requirements）

### 要件 1: リアルタイム文字起こしストリーミング（Realtime Transcription Streaming）

**ユーザーストーリー:** ユーザーとして、録音中にリアルタイムで文字起こし結果を確認したい。それにより、録音完了を待たずに音声の内容をテキストで把握できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが録音を開始した場合、THE TranscribeStreamingClient SHALL SystemAudioCapture から取得した AudioStream を Amazon Transcribe Streaming API にリアルタイムで送信する
2. WHILE 録音中の間、THE TranscribeStreamingClient SHALL Amazon Transcribe Streaming API から受信した PartialTranscript と FinalTranscript を RealtimeTranscriptionViewModel に通知する
3. WHEN Amazon Transcribe Streaming API から FinalTranscript を受信した場合、THE RealtimeTranscriptionViewModel SHALL 確定済みテキストを文字起こし結果に追記する
4. WHEN Amazon Transcribe Streaming API から PartialTranscript を受信した場合、THE RealtimeTranscriptionViewModel SHALL 暫定テキストを現在の確定済みテキストの末尾に表示する
5. WHEN ユーザーが録音を停止した場合、THE TranscribeStreamingClient SHALL ストリーミング接続を正常に終了する
6. THE TranscribeStreamingClient SHALL AudioStream を Amazon Transcribe Streaming API が要求する形式（PCM 16-bit signed little-endian, 16kHz または 48kHz）に変換して送信する
7. IF Amazon Transcribe Streaming API への接続に失敗した場合、THEN THE TranscribeStreamingClient SHALL エラーの内容を含むメッセージを RealtimeTranscriptionViewModel に通知し、録音自体は継続する
8. WHEN ユーザーが録音を停止した場合、THE RealtimeTranscriptionViewModel SHALL リアルタイム文字起こしの最終結果を既存の Transcript モデルとして保持し、後続の要約・エクスポート処理で利用可能にする


### 要件 2: 言語自動判別（Automatic Language Identification）

**ユーザーストーリー:** ユーザーとして、録音中に話されている言語を自動的に判別してほしい。それにより、手動で言語を切り替える手間なく、多言語の音声を文字起こしできるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE TranscribeStreamingClient SHALL Amazon Transcribe Streaming の言語自動判別機能（Automatic Language Identification）を使用して、音声の言語を自動的に判別する
2. THE TranscribeStreamingClient SHALL 言語自動判別の対象言語として日本語（ja-JP）と英語（en-US）を設定する
3. WHEN 言語が判別された場合、THE RealtimeTranscriptionViewModel SHALL 判別された言語名を TranscriptionPreviewPanel に表示する
4. WHERE ユーザーが言語自動判別を無効にした場合、THE TranscribeStreamingClient SHALL ユーザーが手動で選択した言語で文字起こしを実行する
5. THE App SHALL 言語自動判別の有効・無効を切り替えるトグルスイッチを提供する

### 要件 3: リアルタイム翻訳（Realtime Translation）

**ユーザーストーリー:** ユーザーとして、文字起こし結果をリアルタイムで他の言語に翻訳したい。それにより、外国語の音声内容を母国語で即座に理解できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN FinalTranscript が確定した場合、THE TranslateClient SHALL 確定済みテキストを Amazon Translate API を使用して指定された TranslationLanguage に翻訳する
2. WHEN 翻訳が完了した場合、THE RealtimeTranscriptionViewModel SHALL 翻訳結果を TranslationPanel に表示する
3. THE TranslateClient SHALL 以下の翻訳先言語をサポートする:
   - 日本語（ja）
   - 英語（en）
   - 中国語（簡体字）（zh）
   - 韓国語（ko）
   - フランス語（fr）
   - ドイツ語（de）
   - スペイン語（es）
4. THE TranslateClient SHALL 文字起こし結果の言語を翻訳元言語として自動設定する（auto 指定）
5. WHEN ユーザーが翻訳先言語を変更した場合、THE TranslateClient SHALL 既に確定済みの文字起こし結果全体を新しい翻訳先言語で再翻訳する
6. IF Amazon Translate API への呼び出しに失敗した場合、THEN THE TranslateClient SHALL エラーの内容を含むメッセージを RealtimeTranscriptionViewModel に通知し、文字起こし処理は継続する
7. THE TranslateClient SHALL 翻訳リクエストの頻度を制御し、FinalTranscript の確定ごとに1回の翻訳リクエストを送信する（API スロットリングの防止）

### 要件 4: リアルタイム文字起こしプレビュー UI（Realtime Transcription Preview UI）

**ユーザーストーリー:** ユーザーとして、録音中にリアルタイムの文字起こし結果を見やすいパネルで確認したい。それにより、音声の内容をリアルタイムで視覚的に追跡できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE 録音中の間、THE App SHALL TranscriptionPreviewPanel を表示する
2. THE TranscriptionPreviewPanel SHALL 確定済みテキスト（FinalTranscript）を通常のフォントスタイルで表示する
3. THE TranscriptionPreviewPanel SHALL 暫定テキスト（PartialTranscript）を確定済みテキストと視覚的に区別できるスタイル（グレー色・イタリック体）で表示する
4. WHILE 新しいテキストが追加される間、THE TranscriptionPreviewPanel SHALL 自動的に最新のテキスト位置までスクロールする
5. THE TranscriptionPreviewPanel SHALL テキスト選択とコピー操作（.textSelection(.enabled)）をサポートする
6. WHEN 言語自動判別が有効な場合、THE TranscriptionPreviewPanel SHALL 判別された言語名をパネル上部に表示する
7. WHEN 録音が停止した場合、THE TranscriptionPreviewPanel SHALL 最終的な文字起こし結果を表示したまま維持する


### 要件 5: 翻訳結果表示 UI（Translation Result UI）

**ユーザーストーリー:** ユーザーとして、翻訳結果を文字起こし結果とは別のセクションで確認し、翻訳先言語を自由に切り替えたい。それにより、必要な言語の翻訳を即座に取得できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL TranslationPanel を TranscriptionPreviewPanel とは別のセクションとして表示する
2. THE TranslationPanel SHALL 翻訳先言語を選択するドロップダウン（Picker）を提供する
3. THE TranslationPanel SHALL 翻訳結果テキストを表示する
4. THE TranslationPanel SHALL テキスト選択とコピー操作（.textSelection(.enabled)）をサポートする
5. WHILE 翻訳処理中の間、THE TranslationPanel SHALL 処理中であることを示すインジケーターを表示する
6. WHEN 翻訳先言語が変更された場合、THE TranslationPanel SHALL 既存の翻訳結果をクリアし、新しい言語での翻訳結果を表示する
7. WHEN 録音が停止した場合、THE TranslationPanel SHALL 最終的な翻訳結果を表示したまま維持する

### 要件 6: 音声ストリーム連携（Audio Stream Integration）

**ユーザーストーリー:** 開発者として、既存の SystemAudioCapture から取得した音声ストリームを Transcribe Streaming に効率的に送信したい。それにより、既存の録音機能を変更せずにリアルタイム文字起こしを実現したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE TranscribeStreamingClient SHALL SystemAudioCapture の SCStreamOutput / AVCaptureAudioDataOutputSampleBufferDelegate から取得した CMSampleBuffer を受け取るインターフェースを提供する
2. THE TranscribeStreamingClient SHALL CMSampleBuffer から PCM オーディオデータを抽出し、Amazon Transcribe Streaming API が要求する形式に変換する
3. THE SystemAudioCapture SHALL 録音中の音声データを TranscribeStreamingClient にも並行して送信する機能を提供する（既存の録音処理に影響を与えない）
4. IF TranscribeStreamingClient への音声データ送信に失敗した場合、THEN THE SystemAudioCapture SHALL 録音処理を中断せずに継続する
5. WHEN ユーザーが録音を停止した場合、THE TranscribeStreamingClient SHALL 残りの音声バッファを処理してからストリーミング接続を終了する

### 要件 7: エラーハンドリング（Error Handling）

**ユーザーストーリー:** ユーザーとして、リアルタイム文字起こしや翻訳でエラーが発生した場合、原因がわかるメッセージを確認したい。それにより、問題を把握して対処できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. IF AWS 認証情報が未設定の状態でリアルタイム文字起こしが開始された場合、THEN THE App SHALL 「AWS 認証情報が設定されていません。設定画面から認証情報を入力してください」というメッセージを表示する
2. IF Amazon Transcribe Streaming API との接続が切断された場合、THEN THE TranscribeStreamingClient SHALL 自動的に再接続を試みる（最大3回）
3. IF 再接続が3回失敗した場合、THEN THE App SHALL 「リアルタイム文字起こしの接続が切断されました。録音は継続しています」というメッセージを TranscriptionPreviewPanel に表示する
4. IF Amazon Translate API の呼び出しがスロットリングされた場合、THEN THE TranslateClient SHALL 指数バックオフで再試行する（最大3回）
5. IF ネットワーク接続が利用できない場合、THEN THE App SHALL 「ネットワーク接続を確認してください。録音は継続しています」というメッセージを表示する
6. WHEN エラーが発生した場合、THE App SHALL 録音処理自体を中断せず、リアルタイム文字起こし・翻訳のみを停止する

### 要件 8: AWS SDK 依存関係の追加（AWS SDK Dependency Addition）

**ユーザーストーリー:** 開発者として、Amazon Transcribe Streaming と Amazon Translate の AWS SDK モジュールをプロジェクトに追加したい。それにより、ストリーミング文字起こしと翻訳の API を利用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL Swift Package Manager を通じて AWS SDK for Swift の AWSTranscribeStreaming モジュールを依存関係として追加する
2. THE App SHALL Swift Package Manager を通じて AWS SDK for Swift の AWSTranslate モジュールを依存関係として追加する
3. THE App SHALL 既存の依存関係（AWSTranscribe、AWSS3、SwiftCheck）との競合を発生させない
4. THE App SHALL macOS 14（Sonoma）以降との互換性を維持する

### 要件 9: 既存アーキテクチャとの統合（Integration with Existing Architecture）

**ユーザーストーリー:** 開発者として、リアルタイム文字起こし・翻訳機能が既存のアプリケーション構造を壊さないようにしたい。それにより、既存の録音・バッチ文字起こし・要約・エクスポート機能が引き続き正常に動作するようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE RealtimeTranscriptionViewModel SHALL 既存の AppViewModel とは独立した ViewModel として実装する
2. THE App SHALL 録音停止後、リアルタイム文字起こしの最終結果を既存の Transcript モデルに変換し、既存の要約・エクスポート処理で利用可能にする
3. THE App SHALL リアルタイム文字起こし機能の有効・無効を切り替えるトグルスイッチを提供する
4. WHILE リアルタイム文字起こしが無効の間、THE App SHALL 既存のバッチ処理方式（録音完了後に S3 アップロード → Transcribe ジョブ実行）で文字起こしを実行する
5. THE TranscribeStreamingClient SHALL 既存の AWSCredentialManaging プロトコルを使用して認証情報を取得する
6. THE TranslateClient SHALL 既存の AWSCredentialManaging プロトコルを使用して認証情報を取得する
7. THE App SHALL 既存の AppSettingsStore を使用してリアルタイム文字起こし・翻訳の設定（有効/無効、翻訳先言語）を永続化する

### 要件 10: UI レイアウト（UI Layout）

**ユーザーストーリー:** ユーザーとして、すべての機能を1画面で操作でき、不要なセクションは折りたたんで画面を有効活用したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 上下分割レイアウトを採用する（上部: 入力、下部: 出力）
2. THE App SHALL 上部の入力エリアを縦並びで配置する（録音→ファイル→プレーヤーの順）
3. THE App SHALL 下部の出力エリアに3つの折りたたみ可能なセクションを配置する:
   - リアルタイム文字起こし（左: プレビュー、右: 翻訳）
   - 音声文字起こし（左: 結果+ボタン、右: 翻訳）
   - 要約（左: 結果、右: 翻訳）
4. THE App SHALL 各セクションのヘッダーをクリックすることで折りたたみ/展開を切り替えられるようにする
5. THE App SHALL 折りたたみヘッダーに ▶（閉）/ ▼（開）アイコンを表示する
6. THE App SHALL 折りたたみヘッダーのタイトルに「＋翻訳」を含めない
7. THE App SHALL 各テキストエリアにコピーボタンを提供する
8. WHEN 録音/録画が開始された場合、THE App SHALL すべてのテキスト（文字起こし・翻訳・要約）をクリアして初期状態にする
9. THE App SHALL macOS と Windows で同じレイアウト構成を採用する
