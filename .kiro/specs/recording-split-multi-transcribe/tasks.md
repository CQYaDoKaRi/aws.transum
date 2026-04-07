# 実装計画: 録音分割・複数ファイル文字起こし

## 概要

録音ファイルの1分分割保存、複数ファイル対応の音声文字起こし（ファイルリスト UI + 一括文字起こし + 結果結合）、録音開始/停止時のボタン無効化・ステータスバーメッセージ表示、入力グループの不要ラベル削除を実装する。macOS 版を先に実装し、その後 Windows 版に適用する。

## タスク

### macOS 版

- [x] 1. 入力グループのラベル削除と録音ボタン状態制御（macOS）
  - [x] 1.1 `MainView.swift` の `inputArea` 内 `statusContent` クロージャから「録音中」「録画中」テキストラベルと赤い丸インジケーター（`Circle().fill(.red)` + `Text("録音中")` / `Text("録画中")`）を削除する
    - ステータスバーの録音時間表示は維持する
    - _Requirements: 1.1, 1.2, 1.3_
  - [x] 1.2 `AppViewModel.swift` に `isStartingCapture: Bool` と `isStoppingCapture: Bool` の `@Published` プロパティを追加する
    - _Requirements: 2.1, 3.1_
  - [x] 1.3 `AppViewModel.swift` の `statusMessage` 計算プロパティを拡張し、`isStartingCapture` 時に「録音開始中...」、`isStoppingCapture` 時に「録音停止中...」を返すようにする
    - _Requirements: 2.2, 2.4, 3.2, 3.4_
  - [x] 1.4 `startSystemAudioCapture()` を修正: 開始前に `isStartingCapture = true` を設定し、録音ボタンを無効化。開始成功後に `isStartingCapture = false`。エラー時は `isStartingCapture = false` に戻しエラーメッセージを表示
    - _Requirements: 2.1, 2.3, 2.5_
  - [x] 1.5 `stopSystemAudioCapture()` を修正: 停止前に `isStoppingCapture = true` を設定し、停止ボタンを無効化。停止成功後に `isStoppingCapture = false`。エラー時は `isStoppingCapture = false` に戻しエラーメッセージを表示
    - _Requirements: 3.1, 3.3, 3.5_
  - [x] 1.6 `MainView.swift` のツールバーボタンに `.disabled` 修飾子を追加し、`isStartingCapture` / `isStoppingCapture` 中はボタンを無効化する
    - _Requirements: 2.1, 2.3, 3.1, 3.3_

- [x] 2. SplitRecordingManager の実装（macOS）
  - [x] 2.1 `macos/Sources/AudioTranscriptionSummary/Services/SplitRecordingManager.swift` を新規作成する
    - `splitInterval: TimeInterval = 60`（分割間隔）
    - `currentIndex: Int`（現在の連番、1始まり）
    - `splitFiles: [URL]`（生成された分割ファイル一覧）
    - `baseName: String`（タイムスタンプ部分）
    - `outputDirectory: URL`（保存先ディレクトリ）
    - `generateFileName(index:) -> String`: 3桁ゼロ埋め連番付きファイル名を生成（例: `20250101_120000-001.m4a`）
    - `startSplitting(onSplit:)`: 60秒タイマーを起動し、分割時にコールバックを呼ぶ
    - `stopSplitting() -> [URL]`: タイマー停止、最後のファイルを確定、全分割ファイル一覧を返す
    - `reset()`: 連番とファイル一覧をリセット
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
  - [ ]* 2.2 プロパティテスト: 分割ファイル名の生成正確性
    - **Property 1: 分割ファイル名の生成正確性**
    - 任意のベース名と連番（1〜999）に対して、`generateFileName` が `{ベース名}-{3桁ゼロ埋め連番}.m4a` 形式を返すことを検証
    - **Validates: Requirements 4.2, 4.3, 4.4**

- [x] 3. SystemAudioCapture の分割対応（macOS）
  - [x] 3.1 `SystemAudioCapture.swift` に `SplitRecordingManager` を統合する
    - `startCapture()` 内で `SplitRecordingManager` を初期化し、`startSplitting()` を呼ぶ
    - `onSplit` コールバック内で現在の `AVAssetWriter` を確定し、新しい `AVAssetWriter` を開始する
    - 分割切り替え中も音声バッファの欠落を最小限にする
    - _Requirements: 4.1, 4.6, 4.7_
  - [x] 3.2 `stopCapture()` の戻り値を `AudioFile` から分割ファイル配列に変更する
    - `SplitRecordingManager.stopSplitting()` を呼び、全分割ファイルの `AudioFile` 配列を返す
    - 各分割ファイルの duration と fileSize を `AVAsset` / `FileManager` から取得する
    - _Requirements: 4.5, 4.6_
  - [x] 3.3 `cancelCapture()` を修正し、分割中の全ファイルを削除する
    - _Requirements: 4.5_

- [x] 4. チェックポイント - macOS 録音分割の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問してください。

- [x] 5. ファイルリスト UI とデータモデル（macOS）
  - [x] 5.1 `FileListItem` モデルを `Models.swift` に追加する
    - `id: UUID`, `audioFile: AudioFile`, `isSelected: Bool`
    - `durationText: String`（"01:00" 形式）, `fileSizeText: String`（"1.2 MB" 形式）の計算プロパティ
    - _Requirements: 5.2_
  - [x] 5.2 `AppViewModel.swift` に `fileList: [FileListItem]` と `isAllSelected: Bool` の `@Published` プロパティを追加する
    - _Requirements: 5.1, 6.1_
  - [x] 5.3 `AppViewModel.swift` に `addFilesToList(_ urls: [URL]) async` メソッドを実装する
    - `FileImporter` で各 URL を読み込み、`FileListItem(isSelected: true)` として `fileList` の末尾に追加
    - サポート対象外・破損ファイルはスキップし `errorMessage` に記録
    - _Requirements: 5.3, 5.4, 6.3, 6.4_
  - [x] 5.4 `AppViewModel.swift` に `toggleSelectAll()` メソッドを実装する
    - 全ファイルが未選択の場合は全選択、1つ以上選択されている場合は全解除
    - _Requirements: 6.2_
  - [x] 5.5 `AppViewModel.swift` に `removeFilesFromList(_ ids: Set<UUID>)` メソッドを実装する
    - _Requirements: 6.1_
  - [ ]* 5.6 プロパティテスト: ファイル追加時の全選択初期化
    - **Property 3: ファイル追加時の全選択初期化**
    - 任意の数のファイルを追加した場合、追加された全ファイルの `isSelected` が `true` であることを検証
    - **Validates: Requirements 5.3**
  - [ ]* 5.7 プロパティテスト: 手動追加ファイルの末尾追加
    - **Property 4: 手動追加ファイルの末尾追加**
    - 既存リストに手動追加されたファイルが末尾に追加され、既存ファイルの順序が変更されないことを検証
    - **Validates: Requirements 5.4**
  - [ ]* 5.8 プロパティテスト: 全選択/全解除トグル
    - **Property 5: 全選択/全解除トグル**
    - 全ファイルが未選択の場合は全選択に、1つ以上選択されている場合は全解除になることを検証
    - **Validates: Requirements 6.2**

- [x] 6. FileListView の実装（macOS）
  - [x] 6.1 `macos/Sources/AudioTranscriptionSummary/Views/FileListView.swift` を新規作成する
    - ヘッダー: 全選択チェックボックス + 「ファイルを追加」ボタン + 「削除」ボタン
    - 各行: チェックボックス + ファイル名 + 再生時間 + ファイルサイズ
    - `@Binding var fileList: [FileListItem]`
    - `fileImporter` で複数ファイル選択対応（`allowsMultipleSelection: true`）
    - _Requirements: 5.2, 6.1, 6.2, 6.3_
  - [x] 6.2 `FileDropZone.swift` を修正し、複数ファイルのドラッグ＆ドロップに対応する
    - ドロップされた全ファイルを `AppViewModel.addFilesToList()` に渡す
    - _Requirements: 6.4_
  - [x] 6.3 `MainView.swift` の音声文字起こしセクション内に `FileListView` を配置する
    - `FileDropZone` の下、`TranscriptView` の上に配置
    - _Requirements: 5.1, 6.1_

- [x] 7. 録音停止後の分割ファイル自動追加（macOS）
  - [x] 7.1 `stopSystemAudioCapture()` を修正し、録音停止後に全分割ファイルを `fileList` に連番順で追加する
    - 全ファイルを `isSelected: true` で追加
    - _Requirements: 5.1, 5.3_
  - [ ]* 7.2 プロパティテスト: 分割ファイルの連番順追加
    - **Property 2: 分割ファイルの連番順追加**
    - 分割ファイル配列が `fileList` に連番の昇順で追加されることを検証
    - **Validates: Requirements 5.1**

- [x] 8. 複数ファイルの一括文字起こしと結果結合（macOS）
  - [x] 8.1 `AppViewModel.swift` に `transcribeMultipleFiles(language:) async` メソッドを実装する
    - `fileList` で選択されたファイルを選択順に逐次文字起こし
    - 各ファイルの進捗を個別に追跡し、全体進捗を `(i + p) / N` で計算
    - エラーが発生したファイルはスキップし、エラーメッセージにファイル名とエラー内容を追記
    - 全ファイル完了後、結果テキストをファイル順に結合して `transcript` にセット
    - 結合結果を `.transcript.txt` ファイルとして保存
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
  - [x] 8.2 `TranscriptView.swift` の「文字起こし＋要約」ボタンを修正する
    - `fileList` にファイルがある場合は `transcribeMultipleFiles()` を呼ぶ
    - `fileList` が空で `audioFile` がある場合は既存の `transcribeAndSummarize()` を呼ぶ
    - _Requirements: 7.1, 7.4_
  - [ ]* 8.3 プロパティテスト: 文字起こし結果の順序結合
    - **Property 6: 文字起こし結果の順序結合**
    - 任意のテキスト配列に対して、結合結果が配列の順序通りに連結され、内容が欠落・変更されていないことを検証
    - **Validates: Requirements 7.1, 7.3**
  - [ ]* 8.4 プロパティテスト: 複数ファイル文字起こしの全体進捗計算
    - **Property 7: 複数ファイル文字起こしの全体進捗計算**
    - 任意のファイル数 N、インデックス i、個別進捗 p に対して、全体進捗 `(i + p) / N` が 0.0〜1.0 の範囲内であることを検証
    - **Validates: Requirements 7.2**
  - [ ]* 8.5 プロパティテスト: エラー時の文字起こし継続
    - **Property 8: エラー時の文字起こし継続**
    - 任意のファイルリストで任意の位置にエラーが発生した場合、残りのファイルの文字起こしが継続されることを検証
    - **Validates: Requirements 7.6**

- [x] 9. チェックポイント - macOS 版全体の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問してください。

### Windows 版

- [x] 10. 入力グループのラベル削除と録音ボタン状態制御（Windows）
  - [x] 10.1 `MainPage.xaml` の入力セクション内に録音中/録画中ラベルが存在する場合は削除する
    - _Requirements: 1.1, 1.2_
  - [x] 10.2 `MainViewModel.cs` に `IsStartingCapture` と `IsStoppingCapture` の `[ObservableProperty]` を追加する
    - _Requirements: 2.1, 3.1_
  - [x] 10.3 `MainViewModel.cs` の `ProgressMessage` 更新ロジックを拡張し、録音開始中/停止中のメッセージを表示する
    - _Requirements: 2.2, 2.4, 3.2, 3.4_
  - [x] 10.4 `StartCaptureAsync()` を修正: 開始前に `IsStartingCapture = true`、開始成功後に `IsStartingCapture = false`、エラー時は `IsStartingCapture = false` に戻す
    - _Requirements: 2.1, 2.3, 2.5_
  - [x] 10.5 `StopCapture()` を修正: 停止前に `IsStoppingCapture = true`、停止成功後に `IsStoppingCapture = false`、エラー時は `IsStoppingCapture = false` に戻す
    - _Requirements: 3.1, 3.3, 3.5_
  - [x] 10.6 `MainPage.xaml` のツールバーボタンに `IsEnabled` バインディングを追加し、`IsStartingCapture` / `IsStoppingCapture` 中はボタンを無効化する
    - _Requirements: 2.1, 2.3, 3.1, 3.3_

- [x] 11. SplitRecordingManager の実装（Windows）
  - [x] 11.1 `windows/AudioTranscriptionSummary/Services/SplitRecordingManager.cs` を新規作成する
    - macOS 版と同一ロジック（`SplitInterval = 60秒`、3桁ゼロ埋め連番、タイマーベース分割）
    - Windows では `.wav` 形式で保存
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 8.1, 8.2_

- [ ] 12. AudioCaptureService の分割対応（Windows）
  - [ ] 12.1 `AudioCaptureService.cs` に `SplitRecordingManager` を統合する
    - `StartCapture()` 内で `SplitRecordingManager` を初期化し、`StartSplitting()` を呼ぶ
    - `onSplit` コールバック内で現在の `WaveFileWriter` を確定し、新しい `WaveFileWriter` を開始する
    - _Requirements: 4.1, 4.6, 4.7_
  - [ ] 12.2 `StopCapture()` の戻り値を `string` から `List<string>` に変更する
    - _Requirements: 4.5, 4.6_
  - [ ] 12.3 `CancelCapture()` を修正し、分割中の全ファイルを削除する
    - _Requirements: 4.5_

- [ ] 13. ファイルリスト UI とデータモデル（Windows）
  - [ ] 13.1 `FileListItem` モデルを `windows/AudioTranscriptionSummary/Models/FileListItem.cs` に新規作成する
    - macOS 版と同一プロパティ（`Id`, `AudioFile`, `IsSelected`, `DurationText`, `FileSizeText`）
    - _Requirements: 5.2_
  - [ ] 13.2 `MainViewModel.cs` に `FileList`、`IsAllSelected`、`IsStartingCapture`、`IsStoppingCapture` プロパティと `AddFilesToList`、`ToggleSelectAll`、`RemoveFilesFromList`、`TranscribeMultipleFilesAsync` メソッドを追加する
    - macOS 版と同一ロジック
    - _Requirements: 5.1, 5.3, 5.4, 6.1, 6.2, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
  - [ ] 13.3 `MainPage.xaml` の音声文字起こしセクション内にファイルリスト `ListView` を追加する
    - 全選択チェックボックス + ファイル追加ボタン + 削除ボタン
    - 各行: チェックボックス + ファイル名 + 再生時間 + ファイルサイズ
    - 複数ファイルのドラッグ＆ドロップ対応
    - _Requirements: 5.2, 6.1, 6.2, 6.3, 6.4_
  - [ ] 13.4 `MainPage.xaml.cs` のファイル選択ダイアログを複数選択対応に修正する
    - _Requirements: 6.3_

- [ ] 14. 録音停止後の分割ファイル自動追加と一括文字起こし（Windows）
  - [ ] 14.1 `StopCapture` / `MainViewModel` を修正し、録音停止後に全分割ファイルを `FileList` に連番順で追加する
    - _Requirements: 5.1, 5.3_
  - [ ] 14.2 `TranscribeMultipleFilesAsync` を実装し、選択ファイルの逐次文字起こし + 結果結合 + `.transcript.txt` 保存を行う
    - macOS 版と同一ロジック
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_
  - [ ] 14.3 「文字起こし＋要約」ボタンのクリックハンドラを修正し、`FileList` にファイルがある場合は `TranscribeMultipleFilesAsync` を呼ぶ
    - _Requirements: 7.1, 7.4_

- [x] 15. チェックポイント - Windows 版全体の動作確認
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問してください。

### テストと README 更新

- [ ] 16. テストの更新
  - [ ]* 16.1 `SplitRecordingManager` のユニットテストを作成する（`SplitRecordingManagerTests.swift`）
    - `generateFileName` の正確性、`startSplitting` / `stopSplitting` の動作確認
    - _Requirements: 4.2, 4.3, 4.4, 4.5_
  - [ ]* 16.2 `AppViewModel` のファイルリスト操作テストを作成する（`AppViewModelTests.swift` に追加）
    - `addFilesToList`、`toggleSelectAll`、`removeFilesFromList` の動作確認
    - _Requirements: 5.1, 5.3, 5.4, 6.2_
  - [ ]* 16.3 `AppViewModel` の複数ファイル文字起こしテストを作成する
    - 結果結合の順序、進捗計算、エラー時の継続動作の確認
    - _Requirements: 7.1, 7.2, 7.3, 7.6_
  - [ ]* 16.4 録音ボタン状態遷移のテストを作成する
    - `isStartingCapture` / `isStoppingCapture` の状態遷移確認
    - _Requirements: 2.1, 2.3, 2.5, 3.1, 3.3, 3.5_

- [ ] 17. README の更新
  - [x] 17.1 `macos/README.md` に録音分割機能と複数ファイル文字起こし機能の説明を追加する
  - [ ] 17.2 `windows/README.md` に録音分割機能と複数ファイル文字起こし機能の説明を追加する
  - [ ] 17.3 ルートの `README.md` に機能概要を追加する（必要に応じて）

- [x] 18. 最終チェックポイント
  - すべてのテストが通ることを確認し、不明点があればユーザーに質問してください。

## 備考

- `*` マーク付きのタスクはオプションであり、スキップ可能です
- 各タスクは対応する要件番号を参照しています
- チェックポイントで段階的に動作を検証します
- プロパティテストは設計ドキュメントの正確性プロパティに基づいています
