# 実装計画: 音声文字起こし・要約アプリケーション（Audio Transcription Summary）

## 概要

macOS 向け SwiftUI ネイティブアプリケーションを MVVM アーキテクチャで構築する。データモデル・プロトコル定義から始め、各サービス層の実装、ViewModel の統合、View 層の構築の順に進める。各ステップは前のステップの成果物に依存し、最終的にすべてを結合する。音声ファイルに加え、動画ファイルの読み込み・音声抽出、システム音声キャプチャ、画面録画にも対応する。

## タスク

- [x] 1. プロジェクト構造とデータモデルの作成
  - [x] 1.1 Xcode プロジェクトの基本構造とディレクトリを作成する
    - Models/, Services/, ViewModels/, Views/ のグループを作成
    - macOS 14（Sonoma）以降をデプロイメントターゲットに設定
    - SwiftCheck パッケージ依存を追加（テスト用）
    - _要件: 6.1, 6.2_

  - [x] 1.2 データモデル（AudioFile, Transcript, Summary）を実装する
    - `AudioFile` 構造体: id, url, fileName, fileExtension, duration, fileSize, createdAt
    - `Transcript` 構造体: id, audioFileId, text, language, createdAt, isEmpty, characterCount
    - `Summary` 構造体: id, transcriptId, text, createdAt
    - `TranscriptionLanguage` 列挙型: japanese ("ja-JP"), english ("en-US")
    - _要件: 1.5, 2.3, 2.4, 2.5, 3.2_

  - [x] 1.3 AppError 列挙型とサービスプロトコルを定義する
    - `AppError`: unsupportedFormat, corruptedFile, transcriptionFailed, silentAudio, summarizationFailed, insufficientContent, exportFailed, writePermissionDenied
    - `FileImporting`, `Transcribing`, `Summarizing`, `AudioPlaying`, `Exporting` プロトコルを定義
    - _要件: 1.4, 1.6, 2.6, 2.7, 3.5, 3.6, 4.4_

- [x] 2. FileImporter サービスの実装
  - [x] 2.1 FileImporter を実装する
    - サポート形式（m4a, wav, mp3, aiff, mp4, mov, m4v）の判定ロジック
    - AVAsset を用いたファイル読み込みとメタデータ（再生時間、ファイルサイズ）取得
    - ファイル破損時のエラーハンドリング
    - 動画ファイルの場合は AudioExtractor で音声を自動抽出
    - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7_

  - [x]* 2.2 Property 1 のプロパティベーステストを作成する
    - **Property 1: ファイル形式の判定整合性（File Format Validation Consistency）**
    - ランダムなファイル拡張子文字列を生成し、サポート対象形式との判定整合性を検証
    - サポート対象外の拡張子でのエラーメッセージにすべてのサポート対象形式が含まれることを検証
    - **検証対象: 要件 1.3, 1.4**

  - [x]* 2.3 Property 2 のプロパティベーステストを作成する
    - **Property 2: 読み込み後のメタデータ保持（Metadata Preservation After Import）**
    - モックの音声ファイル URL を生成し、読み込み後の AudioFile モデルがファイル名・拡張子・正の再生時間を保持することを検証
    - **検証対象: 要件 1.5**

  - [x]* 2.4 FileImporter のユニットテストを作成する
    - サポート対象形式のファイル読み込み成功テスト
    - 破損ファイルのエラーハンドリングテスト
    - _要件: 1.1, 1.2, 1.3, 1.6_

- [x] 3. Transcriber サービスの実装
  - [x] 3.1 Transcriber を実装する
    - SFSpeechRecognizer の初期化（日本語・英語対応）
    - SFSpeechURLRecognitionRequest による音声認識処理
    - 進捗コールバックの実装
    - 無音検出時の silentAudio エラー返却
    - キャンセル機能の実装
    - _要件: 2.1, 2.2, 2.3, 2.4, 2.5, 2.7_

  - [x]* 3.2 Transcriber のユニットテストを作成する
    - 日本語音声の文字起こしテスト
    - 英語音声の文字起こしテスト
    - 無音ファイルの検出テスト
    - エラー発生時の再試行テスト
    - _要件: 2.4, 2.5, 2.6, 2.7_

- [x] 4. チェックポイント - ファイル読み込みと文字起こしの動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問する。

- [x] 5. Summarizer サービスの実装
  - [x] 5.1 Summarizer を実装する
    - Transcript の文字数チェック（50文字未満は insufficientContent エラー）
    - NaturalLanguage フレームワークを用いたテキスト前処理（文分割）
    - 要約処理の実装
    - _要件: 3.1, 3.3, 3.4, 3.5_

  - [x]* 5.2 Property 3 のプロパティベーステストを作成する
    - **Property 3: 短いテキストの要約拒否（Short Text Summarization Rejection）**
    - 0〜49文字のランダム文字列を生成し、Summarizer が insufficientContent エラーを返すことを検証
    - **検証対象: 要件 3.5**

  - [x]* 5.3 Property 4 のプロパティベーステストを作成する
    - **Property 4: 要約のキーワード保持（Summary Keyword Retention）**
    - 50文字以上のランダムテキストを生成し、生成された Summary が元の Transcript の主要な単語を含むことを検証
    - **検証対象: 要件 3.4**

  - [x]* 5.4 Summarizer のユニットテストを作成する
    - 正常な要約生成テスト
    - エラー発生時の再試行テスト
    - _要件: 3.1, 3.6_

- [x] 6. ExportManager サービスの実装
  - [x] 6.1 ExportManager を実装する
    - Transcript と Summary を UTF-8 の .txt ファイルとして出力
    - 書き込み権限の確認ロジック
    - 権限なし時の writePermissionDenied エラー返却
    - _要件: 4.1, 4.2, 4.3, 4.4_

  - [x]* 6.2 Property 5 のプロパティベーステストを作成する
    - **Property 5: エクスポートのラウンドトリップ（Export Round Trip）**
    - ランダムな Transcript/Summary テキストを生成し、エクスポート後のファイルに元のテキストが含まれることを検証
    - **検証対象: 要件 4.1**

  - [x]* 6.3 ExportManager のユニットテストを作成する
    - 書き込み権限なしのエラーテスト
    - _要件: 4.4_

- [x] 7. AudioPlayer サービスの実装
  - [x] 7.1 AudioPlayer を実装する
    - AVAudioPlayer を用いた音声再生・一時停止
    - シーク機能の実装
    - 再生状態（isPlaying, currentTime, duration）の管理
    - _要件: 5.1, 5.2, 5.3, 5.4_

  - [x]* 7.2 Property 6 のプロパティベーステストを作成する
    - **Property 6: シーク位置の正確性（Seek Position Accuracy）**
    - 0〜duration 範囲のランダムな TimeInterval を生成し、seek 後の currentTime が指定位置と一致することを検証
    - **検証対象: 要件 5.4**

  - [x]* 7.3 AudioPlayer のユニットテストを作成する
    - 再生/一時停止の状態遷移テスト
    - _要件: 5.1, 5.3_

- [x] 8. チェックポイント - 全サービス層の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問する。

- [x] 9. AppViewModel の実装
  - [x] 9.1 AppViewModel を実装する
    - @Published プロパティ（audioFile, transcript, summary, transcriptionProgress, isSummarizing, errorMessage, isPlaying, playbackPosition）の定義
    - importFile: FileImporter を呼び出しファイル読み込み
    - startTranscription: Transcriber を呼び出し文字起こし実行、進捗更新
    - startSummarization: Summarizer を呼び出し要約生成
    - exportResults: ExportManager を呼び出しエクスポート実行
    - togglePlayback / seek: AudioPlayer の再生制御
    - エラーハンドリング: AppError をキャッチし errorMessage に変換
    - 再試行メカニズム: 最後の操作コンテキストを保持し再試行可能にする
    - _要件: 1.4, 1.5, 1.6, 2.2, 2.3, 2.6, 3.2, 3.3, 3.6, 4.3, 5.2_

  - [x]* 9.2 AppViewModel のユニットテストを作成する
    - 起動時の初期状態テスト
    - _要件: 6.4_

- [x] 10. View 層の実装
  - [x] 10.1 MainView とアプリケーションエントリポイントを実装する
    - メインウィンドウのレイアウト構成
    - 起動時のガイダンス表示（音声ファイルの読み込みを促す）
    - ダークモード/ライトモード対応
    - _要件: 6.1, 6.3, 6.4_

  - [x] 10.2 FileDropZone ビューを実装する
    - ドラッグ＆ドロップによるファイル読み込み
    - ファイル選択ダイアログ（Command+O 対応）
    - ファイル情報（ファイル名、形式、再生時間）の表示
    - _要件: 1.1, 1.2, 1.5, 6.5_

  - [x] 10.3 TranscriptView ビューを実装する
    - 文字起こしボタンと言語選択（日本語/英語）
    - プログレスバーによる進捗表示
    - 文字起こし結果のテキストエリア表示
    - _要件: 2.1, 2.2, 2.3_

  - [x] 10.4 SummaryView ビューを実装する
    - 要約ボタンと処理中インジケーター
    - 要約結果の表示（Transcript とは別セクション）
    - _要件: 3.1, 3.2, 3.3_

  - [x] 10.5 AudioPlayerView ビューを実装する
    - 再生/一時停止ボタン
    - シークバーによる再生位置表示と操作
    - _要件: 5.1, 5.2, 5.3, 5.4_

  - [x] 10.6 エラー表示とエクスポート機能を統合する
    - SwiftUI `.alert` によるエラーダイアログ表示
    - 再試行可能なエラーの「再試行」/「閉じる」アクション
    - エクスポートボタンと保存先選択ダイアログ（Command+S 対応）
    - 保存完了メッセージの表示
    - _要件: 2.6, 3.6, 4.1, 4.2, 4.3, 6.5_

- [x] 11. 動画対応・システム音声キャプチャ・画面録画の実装
  - [x] 11.1 AudioExtractor サービスを実装する
    - AVAssetExportSession を用いた動画からの音声トラック抽出（m4a 形式）
    - 音声トラック不在時のエラーハンドリング
    - _要件: 1.7, 1.8_

  - [x] 11.2 SystemAudioCapture サービスを実装する
    - ScreenCaptureKit（SCStream）によるシステム音声キャプチャ
    - AVAssetWriter による直接 M4A（AAC 128kbps, 48kHz）書き出し（MOV 経由の変換を廃止）
    - 音声レベル計算とデリゲート通知
    - キャプチャ開始・停止・キャンセル機能
    - 録音ファイル名: `日付_時刻.m4a`
    - _要件: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x] 11.3 ScreenRecorder サービスを実装する
    - ScreenCaptureKit（SCStream）による画面録画（映像+音声）
    - AVAssetWriter による MOV ファイル書き込み（H.264, 30fps）
    - 録画停止後に AudioExtractor で音声を自動抽出
    - 録画開始・停止・キャンセル機能
    - _要件: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [x] 11.4 SystemAudioCaptureView ビューを実装する
    - システム音声キャプチャと画面録画の開始・停止ボタン
    - 録音/録画中のインジケーター、経過時間、音声レベルメーター
    - 音声抽出中のプログレス表示
    - _要件: 7.1, 7.3, 7.4, 7.6, 8.1, 8.3, 8.5, 8.6_

  - [x] 11.5 AppViewModel にシステム音声キャプチャ・画面録画・音声抽出機能を統合する
    - startSystemAudioCapture / stopSystemAudioCapture / cancelSystemAudioCapture
    - startScreenRecording / stopScreenRecording / cancelScreenRecording
    - 動画ファイル読み込み時の自動音声抽出
    - SystemAudioCaptureDelegate / ScreenRecorderDelegate の実装
    - _要件: 7.2, 7.5, 8.2, 8.4_

  - [x]* 11.6 Property 7 のプロパティベーステストを作成する
    - **Property 7: 動画からの音声抽出整合性（Video Audio Extraction Consistency）**
    - 音声トラック付き動画ファイル（モック）を生成し、抽出後の AudioFile が正の再生時間を持つ m4a 形式であることを検証
    - **検証対象: 要件 1.7**

- [x] 12. 最終チェックポイント - 全体の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問する。

- [x] 13. 音源リソースの選択機能
  - [x] 13.1 AudioSourceType モデルと AudioSourceProvider を作成する
    - `Models/AudioSource.swift` を作成
    - AudioSourceType 列挙型: systemAudio, microphone(deviceID, name), application(bundleID, name)
    - AudioSourceProvider: AVCaptureDevice.DiscoverySession + SCShareableContent から音源一覧を取得
    - _要件: 10.2, 10.3, 10.6_

  - [x] 13.2 SystemAudioCapture にマイク録音対応を追加する
    - startCapture(sourceType:) にマイク分岐を追加
    - マイク: AVCaptureSession + AVCaptureDeviceInput で録音
    - システム音声/アプリ: 従来の ScreenCaptureKit を使用
    - _要件: 10.4, 10.5_

  - [x] 13.3 AppViewModel に音源選択プロパティを追加する
    - selectedAudioSource: AudioSourceType（デフォルト: systemAudio）
    - availableAudioSources: [AudioSourceType]
    - refreshAudioSources(): 利用可能な音源を更新
    - _要件: 10.1, 10.3_

  - [x] 13.4 SystemAudioCaptureView に音源選択 Picker を追加する
    - 録音開始前に音源ドロップダウンを表示
    - .task で画面表示時に音源一覧を自動取得
    - _要件: 10.1_

  - [x] 13.5 録音停止を「保存のみ」に変更する
    - 録音停止後は audioFile に読み込むのみ（文字起こしは自動実行しない）
    - ユーザーが右パネルの「文字起こし＋要約」ボタンで明示的に文字起こしを開始
    - _要件: 10.7, 10.8_

- [x] 14. StatusBarView の実装
  - [x] 14.1 StatusBarView を実装する
    - `Views/StatusBarView.swift` を作成
    - Darwin フレームワークを使用した CPU 使用率・メモリ使用量の取得
    - タイマーによる定期更新
    - メインウィンドウ下部にステータスバーとして配置
    - _要件: 9.1, 9.2, 9.3, 9.4_

- [x] 15. ファイル命名規則の統一とログ改善
  - [x] 15.1 録音ファイル名を `日付_時刻.m4a` に変更する
    - SystemAudioCapture: MOV パススルー → 直接 M4A（AAC）書き出しに変更
    - ファイル名: `yyyyMMdd_HHmmss.m4a`
    - _要件: 4.5, 7.5_

  - [x] 15.2 エクスポートファイル名を元ファイル名ベースに変更する
    - 文字起こし: `元ファイル名.transcript.txt`
    - 要約: `元ファイル名.summary.txt`
    - _要件: 4.5, 4.6_

  - [x] 15.3 ErrorLogger をエラー時のみの出力に変更する
    - デバッグログ（appendLog）を廃止
    - エラーログのみ `日付_時刻.error.log` に1ファイルで出力
    - _要件: 4.7_

- [x] 16. 折りたたみセクションの自動開閉連動
  - [x] 16.1 録音開始/停止時の折りたたみ連動を実装する
    - 録音開始: 入力+リアルタイムを展開、音声文字起こし+要約を折りたたみ
    - 録音停止: 音声文字起こし+要約を展開
    - MainView の `handleCaptureChange` メソッドで制御
    - _要件: 11.1, 11.2_

  - [x] 16.2 FileDropZone にファイル選択コールバックを追加する
    - `onFileSelected` コールバックプロパティを追加
    - D&D（handleDrop）とファイル選択ダイアログ（handleFileImporterResult）の両方でコールバックを呼び出し
    - MainView から入力+リアルタイムを折りたたむクロージャを渡す
    - _要件: 11.3_

  - [x] 16.3 「ファイルから要約」選択時の折りたたみ連動を実装する
    - 要約セクションの fileImporter onCompletion で入力+リアルタイムを折りたたみ
    - _要件: 11.4_

- [x] 17. アプリアイコンの実装
  - [x] 17.1 アプリアイコンをプログラムで生成する
    - 青グラデーション背景 + 白い波形バー + ドキュメントアイコン + 「T」文字
    - NSImage を生成し NSApplication.applicationIconImage に設定
    - _要件: 12.1, 12.2, 12.3_

- [x] 18. macOS インストーラーの作成
  - [x] 18.1 build-app.sh ビルドスクリプトを作成する
    - リリースビルド → .app バンドル作成 → アイコン生成 → DMG 作成
    - Info.plist にマイク・音声認識・画面収録の使用説明を含む
    - Python でアイコン PNG を生成し iconutil で .icns に変換
    - hdiutil で DMG インストーラーを作成
    - _要件: 13.1, 13.2, 13.3, 13.4, 13.5_

- [x] 19. 翻訳パネルリセット連動と案内テキスト削除
  - [x] 19.1 文字起こし/要約テキスト変更時に翻訳パネルをリセットする
    - MainView に onChange(of: viewModel.transcript) で transcriptTranslationVM.reset() を追加
    - MainView に onChange(of: viewModel.summary) で summaryTranslationVM.reset() を追加
    - _要件: 11.5, 11.6_

  - [x] 19.2 結果エリアの操作案内テキストを削除する
    - TranscriptView: 「音声を読み込んで…」テキストを削除
    - SummaryView: 「文字起こし＋要約を実行してください」テキストを削除
    - _要件: 11.7_

- [x] 20. 録音中の UI 制御
  - [x] 20.1 録音中に設定ボタン・ファイル操作・要約ファイルボタン・入力ソース・分割時間を無効化する
    - ツールバーの設定ボタン: `.disabled(isAnyCapturing)`
    - 入力ソース Picker: `.disabled(isCapturing || isRecording)`
    - ファイル分割時間 Picker: `.disabled(isCapturing || isRecording)`
    - FileDropZone に `isDisabled` パラメータを追加し、D&D・ボタンを無効化
    - 要約セクションの「ファイルから要約」ボタン: `.disabled(isAnyCapturing)`
    - _要件: 14.1, 14.2, 14.3, 14.4, 14.6, 14.7_

  - [x] 20.2 ステータスバーに録音経過時間を表示する
    - StatusBarView に `recordingElapsed` 状態変数を追加
    - 録音中は「録音中 MM:SS」を赤色で表示
    - 既存の 2 秒タイマーで経過時間をカウント
    - _要件: 14.5_

  - [x] 20.3 リアルタイム文字起こしの有効/無効トグル動作を実装する（macOS）
    - 無効化時: ストリーミング停止 + コールバック解除 + テキスト全クリア
    - 有効化時（録音中）: startStreaming + コールバック再設定 + ファイル追記
    - _要件: 15.1, 15.2, 15.3, 15.4_

  - [x] 20.4 リアルタイム文字起こしの有効/無効トグル動作を実装する（Windows）
    - MainPage.xaml.cs の OnRealtimeToggled を更新
    - MainViewModel に StopRealtimeStreaming / StartRealtimeStreamingPublicAsync を追加
    - _要件: 15.1, 15.2, 15.3, 15.4_

- [x] 21. 設定の永続化と二重起動防止
  - [x] 21.1 AppSettings に splitIntervalMinutes を追加し、起動時に復元・変更時に保存する（macOS/Windows）
    - _要件: 16.1, 16.3, 16.4_
  - [x] 21.2 isRealtimeEnabled の設定保存を確認する（既存の saveRealtimeSetting で対応済み）
    - _要件: 16.2_
  - [x] 21.3 二重起動防止を実装する（macOS: NSRunningApplication、Windows: Mutex）
    - _要件: 17.1, 17.2_
  - [x] 21.4 設定画面の全項目を変更時に即保存・即反映する（macOS: Combine 自動保存、Windows: ダイアログ保存時に即反映）
    - _要件: 16.5_

- [x] 22. 起動時 AWS 接続テストと設定画面ステータスバー
  - [x] 22.1 起動時に AWS 接続テストを自動実行し、失敗時に設定画面を開く（macOS/Windows）
    - _要件: 18.1, 18.2, 18.3_
  - [x] 22.2 設定画面の下部にステータスバーを追加し、接続ステータスとエラーメッセージを表示する（macOS）
    - 既存のインラインステータスラベルを廃止し、ステータスバーに統合
    - _要件: 18.4_
  - [x] 22.3 Windows 版の設定ダイアログに接続ステータス表示を維持する
    - 既存の connectionPanel（接続テストボタン + ステータスバッジ）を活用
    - _要件: 18.4_

## 備考

- `*` マーク付きのタスクはオプションであり、MVP を優先する場合はスキップ可能
- 各タスクは対応する要件番号を参照しており、トレーサビリティを確保
- チェックポイントで段階的に動作を検証する
- プロパティベーステストは普遍的な正当性を保証し、ユニットテストは具体的なケースを検証する
