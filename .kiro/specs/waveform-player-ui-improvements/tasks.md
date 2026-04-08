# 実装計画: 波形プレーヤーUI改善（Waveform Player UI Improvements）

## 概要

macOS版を先に実装し、動作確認後にWindows版に同等の変更を適用する。
主な変更: (1) FileListView「追加」ボタン削除、(2) Slider→波形表示への置き換え、(3) AudioSpectrumView の削除、(4) 処理中のGUI操作無効化。

## タスク

- [-] 1. [macOS] WaveformDataProvider の実装
  - [x] 1.1 `WaveformDataProvider.swift` を作成し、AVAudioFile からサンプルデータを読み取りダウンサンプリングする `loadWaveformData(from:sampleCount:)` static メソッドを実装する
    - AVAudioFile → AVAudioPCMBuffer でサンプル読み込み
    - 全サンプルを sampleCount 個のビンに分割し、各ビンの最大振幅を取得
    - 結果を 0.0〜1.0 に正規化して `[Float]` で返す
    - エラー時は空配列 `[]` を返す
    - _Requirements: 2.1, 2.8, 7.3_

  - [ ]* 1.2 WaveformDataProvider のプロパティテスト（Property 1: 波形ダウンサンプリングの不変条件）
    - **Property 1: Waveform Downsampling Invariant**
    - 任意の非空サンプル配列と正の sampleCount に対して、出力が正確に sampleCount 個の要素を持ち、各要素が [0.0, 1.0] の範囲内であることを検証
    - **Validates: Requirements 2.1**

  - [ ]* 1.3 WaveformDataProvider のユニットテスト
    - 空ファイル、短い音声、長い音声でのダウンサンプリング結果を検証
    - 存在しないファイルパスで空配列が返ることを検証
    - _Requirements: 2.1_

- [ ] 2. [macOS] WaveformView の実装と AudioPlayerView / AudioSpectrumView の置き換え
  - [x] 2.1 `WaveformView.swift` を作成し、Canvas で波形バーを描画するビューを実装する
    - 再生済み部分を `Color.accentColor`、未再生部分を `Color.gray.opacity(0.4)` で描画
    - 各バーは幅2pt、間隔1ptの縦棒
    - 現在時刻と総再生時間を mm:ss 形式で表示
    - `DragGesture` と `onTapGesture` でシーク操作を実装
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7_

  - [x] 2.2 `AppViewModel` に `waveformData: [Float]` プロパティを追加し、ファイル読み込み時・ファイル切り替え時・録音停止後に波形データを生成する
    - `importFile()`, `selectFileForPlayback()`, `stopSystemAudioCapture()`, `stopScreenRecording()` の各メソッドで `WaveformDataProvider.loadWaveformData()` を呼び出す
    - _Requirements: 2.1_

  - [x] 2.3 `AudioPlayerView.swift` の Slider を `WaveformView` に置き換える
    - 既存の Slider、isDragging/dragPosition ステートを削除
    - WaveformView に waveformData, duration, currentTime, onSeek を渡す
    - _Requirements: 2.2, 2.3_

  - [x] 2.4 `MainView.swift` から `AudioSpectrumView` の参照を削除する
    - `AudioSpectrumView(viewModel:audioLevel:)` の呼び出しを削除
    - _Requirements: 3.1, 3.2_

  - [x] 2.5 `AudioSpectrumView.swift` ファイルを削除する
    - _Requirements: 3.1_

  - [ ]* 2.6 位置→時間マッピングのプロパティテスト（Property 3: Position-to-Time Mapping）
    - **Property 3: Position-to-Time Mapping**
    - 任意の正の width、正の duration、[0, width] 内の x 座標に対して、シーク時間が `(x / width) * duration` に等しく [0, duration] にクランプされることを検証
    - **Validates: Requirements 2.4, 2.5**

  - [ ]* 2.7 時間フォーマットのプロパティテスト（Property 4: Time Formatting Correctness）
    - **Property 4: Time Formatting Correctness**
    - 任意の非負の TimeInterval に対して、フォーマット関数が `MM:SS` 形式を返し、MM = totalSeconds / 60、SS = totalSeconds % 60 であることを検証
    - **Validates: Requirements 2.7**

  - [ ]* 2.8 再生位置の視覚的分割のプロパティテスト（Property 2: Playback Position Visual Split）
    - **Property 2: Playback Position Visual Split**
    - 任意の正の duration と [0, duration] 内の currentTime に対して、再生済みバーの割合が `currentTime / duration` に等しいこと（±1バーの誤差許容）を検証
    - **Validates: Requirements 2.3**

- [ ] 3. [macOS] 処理中のGUI操作無効化
  - [x] 3.1 `AppViewModel` に `isProcessing` 計算プロパティを追加する（`isTranscribing || isSummarizing`）
    - _Requirements: 4.1, 5.1, 6.1_

  - [x] 3.2 `MainView.swift` のツールバーボタン（録音、設定）に `.disabled(viewModel.isProcessing)` を追加する
    - 既存の `isAnyCapturing` 条件に `viewModel.isProcessing` を OR で追加
    - _Requirements: 4.2, 5.2, 6.2_

  - [x] 3.3 `MainView.swift` の入力エリア内コントロール（音源 Picker、リアルタイムトグル）に `.disabled(viewModel.isProcessing)` を追加する
    - _Requirements: 4.4_

  - [x] 3.4 `FileDropZone` の `isDisabled` パラメータに `viewModel.isProcessing` を OR で追加する
    - _Requirements: 4.3, 5.3, 6.3_

  - [x] 3.5 `FileListView`、`AudioPlayerView`（WaveformView）、`TranscriptView`、要約セクションのコントロールに `.disabled(viewModel.isProcessing)` と `.opacity(viewModel.isProcessing ? 0.5 : 1.0)` を追加する
    - _Requirements: 4.5, 5.4, 6.4_

  - [ ]* 3.6 isProcessing 計算プロパティのプロパティテスト（Property 5: isProcessing Computation）
    - **Property 5: isProcessing Computation**
    - 任意の isTranscribing と isSummarizing のブール値の組み合わせに対して、isProcessing が `isTranscribing || isSummarizing` に等しいことを検証
    - **Validates: Requirements 4.1, 5.1, 6.1**

- [x] 4. チェックポイント - macOS版の動作確認
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

- [-] 5. [Windows] WaveformDataProvider の実装
  - [ ] 5.1 `WaveformDataProvider.cs` を `Services/` に作成し、NAudio AudioFileReader からサンプルデータを読み取りダウンサンプリングする `LoadWaveformData(filePath, sampleCount)` static メソッドを実装する
    - AudioFileReader でサンプル読み込み
    - 全サンプルを sampleCount 個のビンに分割し、各ビンの最大振幅を取得
    - 結果を 0.0〜1.0 に正規化して `float[]` で返す
    - エラー時は空配列を返す
    - _Requirements: 2.1, 2.9, 7.4_

  - [ ]* 5.2 WaveformDataProvider のユニットテスト
    - _Requirements: 2.1_

- [ ] 6. [Windows] 波形表示コントロールの実装と既存コントロールの置き換え
  - [ ] 6.1 `MainViewModel.cs` に `WaveformData` プロパティと `IsProcessing` 計算プロパティを追加する
    - ファイル読み込み時・ファイル切り替え時・録音停止後に波形データを生成
    - `IsProcessing` は `IsTranscribing || IsSummarizing` を返す
    - _Requirements: 2.1, 4.1, 5.1, 6.1_

  - [ ] 6.2 `MainPage.xaml` の `PlayerPanel` 内の Slider を Canvas ベースの波形表示に置き換え、`SpectrumPanel` を削除する
    - XAML Canvas 上に Rectangle 要素で波形バーを描画
    - 再生済み部分: `#0078D4`、未再生部分: `#C0C0C0`
    - PointerPressed / PointerMoved イベントでシーク操作を実装
    - 時間表示（mm:ss）を維持
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.9, 3.1, 3.2_

  - [ ] 6.3 `MainPage.xaml.cs` のスペクトラム関連コード（`InitializeSpectrumBars`, `UpdateSpectrumBars`）を削除し、波形描画・シーク処理のコードビハインドを実装する
    - _Requirements: 3.1_

  - [ ] 6.4 `MainPage.xaml` のファイルリストヘッダーから「追加」ボタン（`FileListAddBtn`）を削除する
    - _Requirements: 1.4_

- [ ] 7. [Windows] 処理中のGUI操作無効化
  - [ ] 7.1 `MainPage.xaml.cs` の PropertyChanged ハンドラに `IsProcessing` の監視を追加し、処理中にツールバーボタン、DropZone、Picker、ファイルリスト、要約ボタン等を無効化する
    - `RecordButton`, `SettingsButton`, `FilePickButton`, `DropZone.AllowDrop`, `AudioSourcePicker`, `TranscriptionLangCombo`, `BedrockModelCombo`, `SummaryFileBtn`, `ResummarizeBtn`, `RealtimeToggle`, `FileListPanel`, `PlayerPanel` を対象
    - _Requirements: 4.1〜4.5, 5.1〜5.4, 6.1〜6.4, 7.2, 7.5_

- [x] 8. 最終チェックポイント - 全テスト通過確認
  - すべてのテストが通ることを確認し、ユーザーに質問があれば確認する。

## 備考

- `*` マーク付きのタスクはオプションであり、スキップ可能
- 各タスクは要件定義書の具体的な要件番号を参照
- チェックポイントで段階的に動作確認を実施
- プロパティテストは設計書の正当性プロパティに基づく
