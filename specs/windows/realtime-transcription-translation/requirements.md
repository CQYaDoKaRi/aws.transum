# 要件定義ドキュメント（Requirements Document）- Windows版

## はじめに（Introduction）

本ドキュメントは、Windows版音声文字起こし・要約アプリケーション（WinUI 3 / .NET 8）に、Amazon Transcribe Streamingによるリアルタイム文字起こしとAmazon Translateによるリアルタイム翻訳機能を追加するための要件を定義する。

## 用語集（Glossary）

- **App**: Windows版AudioTranscriptionSummaryアプリケーション（WinUI 3 / .NET 8）
- **TranscribeStreamingClient**: Amazon Transcribe Streaming APIと通信し、リアルタイム文字起こしを行うコンポーネント
- **TranslateClient**: Amazon Translate APIと通信し、テキストを翻訳するコンポーネント
- **AudioCaptureService**: NAudioでシステム音声・マイクをキャプチャするコンポーネント（既存）
- **RealtimeTranscriptionViewModel**: リアルタイム文字起こし・翻訳の状態管理ViewModel
- **TranscriptionPreviewPanel**: リアルタイム文字起こし結果を表示するUIパネル
- **TranslationPanel**: 翻訳結果を表示するUIパネル
- **PartialTranscript**: 暫定的な文字起こし結果（確定前）
- **FinalTranscript**: 確定済みの文字起こし結果
- **TranslationLanguage**: 翻訳先言語（日本語・英語・中国語・韓国語・フランス語・ドイツ語・スペイン語）

## 要件（Requirements）

### 要件 1: リアルタイム文字起こしストリーミング（Realtime Transcription Streaming）

**ユーザーストーリー:** ユーザーとして、録音中にリアルタイムで文字起こし結果を確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが録音を開始した場合、THE TranscribeStreamingClient SHALL AudioCaptureServiceから取得した音声をAmazon Transcribe Streaming APIにリアルタイムで送信する
2. WHILE 録音中の間、THE TranscribeStreamingClient SHALL PartialTranscriptとFinalTranscriptをRealtimeTranscriptionViewModelに通知する
3. WHEN FinalTranscriptを受信した場合、THE RealtimeTranscriptionViewModel SHALL 確定済みテキストを追記する
4. WHEN PartialTranscriptを受信した場合、THE RealtimeTranscriptionViewModel SHALL 暫定テキストを末尾に表示する
5. WHEN ユーザーが録音を停止した場合、THE TranscribeStreamingClient SHALL ストリーミング接続を終了する
6. THE TranscribeStreamingClient SHALL 音声をPCM 16-bit signed LE, 16kHzに変換して送信する
7. IF 接続に失敗した場合、THEN THE TranscribeStreamingClient SHALL エラーを通知し、録音自体は継続する
8. WHEN 録音停止後、THE RealtimeTranscriptionViewModel SHALL 最終結果をRealtimeTranscriptionVM内に保持する（Transcriptフィールドには設定しない。Transcriptはバッチ文字起こしでのみ設定される）

### 要件 2: 言語自動判別（Automatic Language Identification）

**ユーザーストーリー:** ユーザーとして、録音中に話されている言語を自動判別してほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE TranscribeStreamingClient SHALL 言語自動判別機能を使用して日本語（ja-JP）と英語（en-US）を判別する
2. WHEN 言語が判別された場合、THE App SHALL 判別された言語名をバッジとして表示する
3. WHERE ユーザーが言語自動判別を無効にした場合、THE TranscribeStreamingClient SHALL 手動選択された言語で文字起こしを実行する
4. THE App SHALL 言語自動判別の有効・無効を切り替えるToggleSwitchを設定画面に提供する

### 要件 3: リアルタイム翻訳（Realtime Translation）

**ユーザーストーリー:** ユーザーとして、文字起こし結果をリアルタイムで他の言語に翻訳したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN FinalTranscriptが確定した場合、THE TranslateClient SHALL AWSSDK.Translateを使用して指定言語に翻訳する
2. THE TranslateClient SHALL 日本語(ja)・英語(en)・中国語(zh)・韓国語(ko)・フランス語(fr)・ドイツ語(de)・スペイン語(es)をサポートする
3. THE TranslateClient SHALL 翻訳元言語をauto指定する
4. WHEN ユーザーが翻訳先言語を変更した場合、THE TranslateClient SHALL 確定済みテキスト全体を再翻訳する
5. IF 翻訳APIの呼び出しに失敗した場合、THEN THE TranslateClient SHALL 指数バックオフで最大3回再試行する（1s, 2s, 4s）
6. THE TranslateClient SHALL FinalTranscript確定ごとに1回の翻訳リクエストを送信する

### 要件 4: リアルタイム文字起こしプレビューUI（Realtime Transcription Preview UI）

**ユーザーストーリー:** ユーザーとして、録音中にリアルタイムの文字起こし結果を見やすいパネルで確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE 録音中の間、THE App SHALL TranscriptionPreviewPanelを表示する
2. THE TranscriptionPreviewPanel SHALL 確定済みテキストを通常スタイルで表示する
3. THE TranscriptionPreviewPanel SHALL 暫定テキストをグレー色で視覚的に区別して表示する
4. WHILE 新しいテキストが追加される間、THE TranscriptionPreviewPanel SHALL 自動スクロールする
5. THE TranscriptionPreviewPanel SHALL テキスト選択（IsTextSelectionEnabled）とコピーをサポートする
6. WHEN 言語自動判別が有効な場合、THE TranscriptionPreviewPanel SHALL 判別された言語名を表示する

### 要件 5: 翻訳結果表示UI（Translation Result UI）

**ユーザーストーリー:** ユーザーとして、翻訳結果を文字起こし結果とは別のセクションで確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL TranslationPanelをTranscriptionPreviewPanelの右側に表示する
2. THE TranslationPanel SHALL 翻訳先言語を選択するComboBoxを提供する
3. THE TranslationPanel SHALL 翻訳結果テキストを表示する
4. THE TranslationPanel SHALL テキスト選択とコピーをサポートする
5. WHILE 翻訳処理中の間、THE TranslationPanel SHALL ProgressRingを表示する
6. THE App SHALL リアルタイム・バッチ文字起こし・要約の各セクションにTranslationPanelを配置する

### 要件 6: 音声ストリーム連携（Audio Stream Integration）

**ユーザーストーリー:** 開発者として、既存のAudioCaptureServiceから取得した音声をTranscribe Streamingに効率的に送信したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE TranscribeStreamingClient SHALL AudioCaptureServiceのDataAvailableイベントからPCMデータを受け取るインターフェースを提供する
2. THE TranscribeStreamingClient SHALL NAudioのWaveFormatからPCM 16kHz 16-bit monoに変換する
3. THE AudioCaptureService SHALL 録音中の音声データをTranscribeStreamingClientにも並行して送信する
4. IF TranscribeStreamingClientへの送信に失敗した場合、THEN THE AudioCaptureService SHALL 録音を中断せずに継続する

### 要件 7: エラーハンドリング（Error Handling）

**ユーザーストーリー:** ユーザーとして、リアルタイム文字起こしや翻訳でエラーが発生した場合、原因がわかるメッセージを確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. IF AWS認証情報が未設定の場合、THEN THE App SHALL 「AWS認証情報が設定されていません」というメッセージを表示する
2. IF Transcribe Streaming接続が切断された場合、THEN THE TranscribeStreamingClient SHALL 自動再接続を試みる（最大3回）
3. IF 再接続が3回失敗した場合、THEN THE App SHALL 「リアルタイム文字起こしの接続が切断されました。録音は継続しています」と表示する
4. IF Translate APIがスロットリングされた場合、THEN THE TranslateClient SHALL 指数バックオフで再試行する
5. WHEN エラーが発生した場合、THE App SHALL 録音処理自体を中断せず、リアルタイム文字起こし・翻訳のみを停止する

### 要件 8: AWS SDK依存関係の追加（AWS SDK Dependency Addition）

**ユーザーストーリー:** 開発者として、Amazon Transcribe StreamingとAmazon TranslateのSDKモジュールを使用したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL NuGetを通じてAWSSDK.TranscribeService 4.*（Streaming API含む）を使用する
2. THE App SHALL NuGetを通じてAWSSDK.Translate 4.* を依存関係として使用する
3. THE App SHALL 既存の依存関係との競合を発生させない

### 要件 9: 既存アーキテクチャとの統合（Integration with Existing Architecture）

**ユーザーストーリー:** 開発者として、リアルタイム文字起こし・翻訳機能が既存のアプリケーション構造を壊さないようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE RealtimeTranscriptionViewModel SHALL CommunityToolkit.MvvmのObservableObjectを継承する
2. THE App SHALL 録音停止後、リアルタイム文字起こしの最終結果をRealtimeTranscriptionVM内に保持する（Transcriptフィールドはバッチ文字起こしでのみ設定される）
3. THE App SHALL リアルタイム文字起こし機能の有効・無効をToggleSwitchで切り替え可能にする
4. WHILE リアルタイム文字起こしが無効の間、THE App SHALL リアルタイムセクションを非表示にする
5. THE App SHALL SettingsStoreを使用してリアルタイム設定を永続化する

### 要件 10: UIレイアウト（UI Layout）

**ユーザーストーリー:** ユーザーとして、すべての機能を1画面で操作でき、不要なセクションは折りたたんで画面を有効活用したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 上下分割レイアウトを採用する（上部: 入力、下部: 出力）
2. THE App SHALL 下部の出力エリアに3つの折りたたみ可能なExpanderセクションを配置する（各ヘッダーに色付き背景とFontIconアイコン）:
   - リアルタイム文字起こし（赤 #20E74856、左: プレビュー、右: 翻訳）
   - 音声文字起こし（緑 #2016C60C、左: 結果+ボタン、右: 翻訳）
   - 要約（オレンジ #20F7630C、左: 結果、右: 翻訳）
3. THE App SHALL 各Expanderヘッダーをクリックで折りたたみ/展開を切り替えられるようにする
4. THE App SHALL 各テキストエリアにコピーボタン（FontIcon &#xE8C8;）を提供し、テキストエリアにBorderフレーム（BorderThickness=1, CornerRadius=4）を適用する
5. WHEN 録音が開始された場合、THE App SHALL すべてのテキストをクリアして初期状態にする
6. THE App SHALL macOSと同じレイアウト構成を採用する
