# 実装計画: 音声文字起こし・要約アプリケーション（Windows版）

## 概要

WinUI 3 / .NET 8 ネイティブアプリケーションをMVVMアーキテクチャで構築する。データモデル・サービス層から始め、ViewModel統合、View層の順に進める。NAudioによる音声キャプチャ・再生、抽出型要約、ファイルインポート・エクスポート機能を実装する。

## タスク

- [x] 1. プロジェクト構造とデータモデルの作成
  - [x] 1.1 プロジェクトのディレクトリ構造を整理する
    - Models/, Services/, ViewModels/, Views/ フォルダを作成
    - 既存のスタブファイルを適切なフォルダに移動
    - _要件: 6.1, 6.2_

  - [x] 1.2 データモデル（AudioFile, Transcript, Summary）を実装する
    - `AudioFile` record: Id, FilePath, FileName, Extension, Duration, FileSize, CreatedAt
    - `Transcript` record: Id, AudioFileId, Text, Language, CreatedAt
    - `Summary` record: Id, TranscriptId, Text, CreatedAt
    - _要件: 1.5, 2.3, 3.3_

  - [x] 1.3 AppError クラスとAppSettings モデルを実装する
    - `AppError` : UnsupportedFormat, CorruptedFile, TranscriptionFailed, SilentAudio, SummarizationFailed, InsufficientContent, ExportFailed, WritePermissionDenied, CredentialsNotSet
    - `AppSettings` : AccessKeyId, SecretAccessKey, Region, S3BucketName, RecordingDirectoryPath, ExportDirectoryPath, IsRealtimeEnabled, IsAutoDetectEnabled, DefaultTargetLanguage
    - _要件: 1.4, 2.5, 3.4_

- [x] 2. SettingsStore サービスの実装
  - [x] 2.1 SettingsStore を実装する
    - %APPDATA%\AudioTranscriptionSummary\settings.json に永続化
    - Load(): JSONファイルから読み込み、存在しない/破損時はデフォルト値を返す
    - Save(): JSONファイルに書き込み、親ディレクトリを自動作成
    - System.Text.Json使用
    - _要件: W1.1, W1.2, W1.3, W1.4, W1.5_

- [x] 3. FileImporter サービスの実装
  - [x] 3.1 FileImporter を実装する
    - サポート形式: m4a, wav, mp3, aiff, mp4, mov, m4v
    - NAudio AudioFileReaderでメタデータ（Duration）取得
    - ファイル破損時のエラーハンドリング
    - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 4. AudioCaptureService の実装
  - [x] 4.1 AudioCaptureService を実装する
    - WaveInEvent でマイクデバイス列挙・キャプチャ
    - WasapiLoopbackCapture でシステム音声キャプチャ
    - WaveFileWriter でWAV保存
    - 音声レベル計算（RMS → 0.0-1.0）
    - DataAvailableイベントでリアルタイムストリーミング用データ提供
    - 開始・停止・キャンセル機能
    - _要件: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

- [x] 5. AudioPlayerService の実装
  - [x] 5.1 AudioPlayerService を実装する
    - NAudio WaveOutEvent + AudioFileReader
    - Play/Pause/Seek
    - PositionChangedイベント（100ms間隔）
    - 終端到達時の自動停止・リセット
    - _要件: 5.1, 5.2, 5.3, 5.4, 5.5_

- [x] 6. Summarizer サービスの実装
  - [x] 6.1 Summarizer を実装する
    - 文分割（。！？.!? で分割）
    - 単語頻度スコアリング（最大値で正規化）
    - 位置スコアリング（先頭1.0、末尾0.5、中間漸減）
    - 長さスコアリング
    - 上位約30%（最低1文）を選択、元の順序保持
    - 50文字未満はInsufficientContentエラー
    - _要件: 3.1, 3.2, 3.3, 3.4, 3.5_

- [x] 7. ExportManager サービスの実装
  - [x] 7.1 ExportManager を実装する
    - {baseName}.transcript.txt / {baseName}.summary.txt
    - "=== Transcript ===" / "=== Summary ===" ヘッダー
    - UTF-8エンコーディング
    - 書き込み権限チェック
    - _要件: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 8. StatusMonitor の実装
  - [x] 8.1 StatusMonitor を実装する
    - System.Diagnostics.Process でアプリCPU/メモリ取得
    - GC.GetGCMemoryInfo() でマネージドメモリ
    - Environment.WorkingSet でアプリメモリ
    - 2秒間隔で更新
    - _要件: 9.1, 9.2, 9.3, 9.4, 9.5_

- [x] 9. チェックポイント - 全サービス層の動作確認

- [x] 10. MainViewModel の実装
  - [x] 10.1 MainViewModel を実装する
    - CommunityToolkit.Mvvm ObservableObject
    - ObservableProperty: AudioFile, Transcript, Summary, TranscriptionProgress, IsCapturing, AudioLevel, ErrorMessage, IsPlaying, PlaybackPosition, AudioSources, SelectedSource
    - RelayCommand: ImportFile, TranscribeAndSummarize, Export, StartCapture, StopCapture, CancelCapture, TogglePlayback, Seek
    - エラーハンドリング: AppErrorをキャッチしErrorMessageに変換
    - 再試行メカニズム
    - _要件: 2.2, 2.5, 2.7, 3.3, 4.3, 6.5_

- [x] 11. View層の実装
  - [x] 11.1 MainPage.xaml を完全なレイアウトで再実装する
    - CommandBar: 録音/停止、キャンセル、エクスポート、設定
    - Expander: 入力、リアルタイム文字起こし、音声文字起こし、要約
    - 各セクション左右2列（元テキスト | 翻訳）
    - ステータスバー右寄せ
    - _要件: 6.1, 6.4, W6.1, W6.2_

  - [x] 11.2 設定ダイアログ（ContentDialog）を実装する
    - TextBox: Access Key ID
    - PasswordBox: Secret Access Key
    - ComboBox: リージョン（12リージョン）
    - TextBox: S3バケット名
    - FolderPicker: 録音保存先、エクスポート保存先
    - ToggleSwitch: リアルタイム文字起こし、言語自動判別
    - ComboBox: デフォルト翻訳先言語
    - 保存/接続テスト/削除ボタン
    - 接続ステータスバッジ
    - _要件: W2.1-W2.5_

  - [x] 11.3 AudioPlayerControl を実装する
    - Play/Pause Button
    - Position Slider + time display "mm:ss / mm:ss"
    - MainViewModelにバインド
    - _要件: 5.1, 5.2, 5.3, 5.4_

  - [x] 11.4 ドラッグ＆ドロップとファイル選択を実装する
    - AllowDrop, DragOver, Drop イベント
    - FileOpenPicker
    - _要件: 1.1, 1.2, W7.1, W7.2_

  - [x] 11.5 コピーボタンを全テキストエリアに実装する
    - DataPackage + Clipboard.SetContent
    - 6箇所: リアルタイム文字起こし/翻訳、バッチ文字起こし/翻訳、要約/翻訳
    - _要件: C7.1, C7.2_

  - [x] 11.6 エラーダイアログと再試行を実装する
    - ContentDialog でエラーメッセージ表示
    - 再試行可能なエラーには「再試行」ボタン
    - _要件: 2.5, 3.4_

- [x] 12. ファイル命名規則の統一
  - [x] 12.1 全生成ファイルのファイル名を yyyyMMdd_HHmmss 形式にする
    - 録音: yyyyMMdd_HHmmss.wav（プレフィックスなし）
    - 文字起こし: {音声ファイル名}.transcript.txt
    - 要約: {音声ファイル名}.summary.txt
    - ファイルから要約: {読み込みファイル名}.summary.txt
    - _要件: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 13. ビルド・起動の確認
  - [x] 13.1 VS Community MSBuildでクリーンビルドし、アプリが正常に起動することを確認する

- [x] 14. 折りたたみセクションの自動開閉連動
  - [x] 14.1 各Expanderにx:Nameを付与する
    - InputSection, RealtimeSection, TranscriptSection, SummarySection
    - _要件: 11.1, 11.2, 11.3, 11.4_

  - [x] 14.2 録音開始/停止時の折りたたみ連動を実装する
    - UpdateRecordingUI()で録音開始時に入力+リアルタイムを展開、文字起こし+要約を折りたたみ
    - 録音停止時に文字起こし+要約を展開
    - _要件: 11.1, 11.2_

  - [x] 14.3 ファイル選択時の折りたたみ連動を実装する
    - OnDrop、OnFilePickClickでCollapseInputAndRealtime()を呼び出し
    - _要件: 11.3_

  - [x] 14.4 「ファイルから要約」選択時の折りたたみ連動を実装する
    - OnSummaryFileClickでCollapseInputAndRealtime()を呼び出し
    - _要件: 11.4_

  - [x] 14.5 SummarizeFromFileCommandをMainViewModelに追加する
    - テキストファイルを読み込んでTranscriptを生成し要約を実行
    - _要件: 11.4_

- [x] 15. アプリアイコンの実装
  - [x] 15.1 AppIconGenerator サービスを作成する
    - System.Drawing.Common で青グラデーション背景 + 白い波形バー + ドキュメントアイコン + 「T」文字のICOファイルを生成
    - %APPDATA%\AudioTranscriptionSummary\app.ico にキャッシュ
    - _要件: 17.2, 17.3, 17.4_

  - [x] 15.2 MainWindow でアイコンを設定する
    - AppWindow.SetIcon() でタイトルバー＋タスクバーにアイコンを表示
    - _要件: 17.1_

- [x] 16. TranscriptionLanguage の実装
  - [x] 16.1 TranscriptionLanguage 列挙型を実装する
    - Models/TranscriptionLanguage.cs: 21言語＋Auto
    - ToCode() / ToDisplayName() 拡張メソッド
    - _要件: 13.1_

  - [x] 16.2 TranscriptionLangCombo を MainPage に追加する
    - 「文字起こし＋要約」ボタンの横に配置
    - 選択変更時に MainViewModel.SelectedTranscriptionLanguage を更新
    - _要件: 13.2, 13.3, 13.4_

- [x] 17. テキストクリア動作の実装
  - [x] 17.1 文字起こし開始時のクリアを実装する
    - Transcript, Summary, 各翻訳テキストをクリア
    - _要件: 14.1_

  - [x] 17.2 Transcript設定/クリア時の翻訳クリアを実装する
    - TranscriptTranslationText をクリア
    - _要件: 14.2_

  - [x] 17.3 要約開始時のクリアを実装する
    - Summary, SummaryTranslationVM をクリア
    - _要件: 14.3_

  - [x] 17.4 録音開始時の全テキストクリアを実装する
    - リアルタイム、文字起こし、要約、各翻訳をすべてクリア
    - _要件: 14.4_

- [x] 18. ボタン状態管理の実装
  - [x] 18.1 ボタンの有効/無効制御を実装する
    - 文字起こしボタン: 音声ファイル未選択時/文字起こし中に無効
    - ファイルから要約/要約ボタン: 文字起こし中/要約中に無効
    - コピーボタン: テキスト空時に無効
    - 翻訳ボタン: ソーステキスト空時に無効
    - 要約中ProgressRing表示
    - 録音中: 設定ボタン、ファイル選択、D&D、ファイルから要約、要約ボタンを無効化
    - _要件: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6_

- [x] 19. テキストエリアの高さ統一とリサイズの実装
  - [x] 19.1 テキストエリアの初期高さを150pxに統一する
    - _要件: 16.1_

  - [x] 19.2 SizeChangedハンドラでリサイズ対応を実装する
    - 最小高さ150px
    - _要件: 16.2, 16.3_

- [x] 20. ErrorLogger の実装
  - [x] 20.1 ErrorLogger サービスを実装する
    - Services/ErrorLogger.cs: Mac互換エラーログ
    - yyyyMMdd_HHmmss.error.log に詳細情報を記録
    - _要件: 関連する全エラーハンドリング_

- [x] 21. 録音時間表示の実装
  - [x] 21.1 録音経過時間をステータスバーに表示する
    - _captureStartTime で録音開始時刻を記録
    - UpdateStatus() で2秒ごとに「音声をキャプチャ中... mm:ss」を更新
    - 録音停止/キャンセル時にクリア
    - _要件: 18.1, 18.2, 18.3_

- [x] 22. リアルタイム文字起こしトグルの実装
  - [x] 22.1 入力セクションにToggleSwitchを配置する
    - OnContent/OffContent で「リアルタイム文字起こし」を表示
    - トグル変更時に設定保存・リアルタイムセクション表示切替
    - _要件: 19.1, 19.2, 19.3_

- [x] 23. 設定画面のUI改善
  - [x] 23.1 設定画面のサイズ拡大
    - MinWidth=1100, FullSizeDesired=true, ContentDialogMaxWidth=1200, ContentDialogMaxHeight=1200
    - フォルダ選択ボタンをテキストエリアと同じ行に右寄せ配置（Grid レイアウト）
    - 入力ソースComboBoxのHeaderラベル削除
    - 基盤モデルComboBoxのMinWidth=350（モデル名が途切れない幅）
    - _要件: 関連するUI要件_

## 備考

- `*` マーク付きのタスクはオプション
- 各タスクは対応する要件番号を参照
- チェックポイントで段階的に動作を検証
