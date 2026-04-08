# 要件定義書（Requirements Document）

## はじめに

音声文字起こし＋要約アプリケーション（macOS SwiftUI / Windows WinUI 3）のUI改善に関する要件定義書。
主な改善点は以下の通り:
1. FileListView の「追加」ボタン削除
2. 音声プレーヤーのスライダーを波形表示（Waveform）に置き換え、再生位置を視覚的に表示
3. 処理中（文字起こし＋要約、ファイルから要約、要約）のGUI操作無効化
4. macOS / Windows 両プラットフォーム対応

## 用語集（Glossary）

- **App**: 音声文字起こし＋要約アプリケーション（macOS版 / Windows版の総称）
- **FileListView**: 音声文字起こしセクション内のファイルリスト表示コンポーネント
- **Waveform_Display**: 音声ファイルの波形を描画し、再生位置を視覚的に示すUIコンポーネント
- **Audio_Player**: 音声ファイルの再生・一時停止・シーク操作を提供するコンポーネント
- **Processing_State**: 文字起こし、要約、ファイルから要約のいずれかの処理が実行中である状態
- **GUI_Controls**: ボタン、Picker、テキスト入力、ファイルドロップゾーンなどのユーザー操作可能なUI要素の総称

## 要件（Requirements）

### 要件 1: FileListView の「追加」ボタン削除

**ユーザーストーリー:** 開発者として、FileListView のヘッダーから「追加」ボタンを削除したい。ファイル追加はドラッグ＆ドロップまたはドロップゾーンの「ファイル追加」ボタンから行えるため、FileListView 内の「追加」ボタンは冗長である。

#### 受け入れ基準（Acceptance Criteria）

1. THE FileListView SHALL display only the select-all checkbox and the delete button in the header area
2. WHEN a user wants to add files, THE App SHALL provide file addition through the FileDropZone component and the file picker button in the drop zone
3. THE FileListView on macOS SHALL not contain an add button or file importer trigger in the header
4. THE FileListView on Windows SHALL not contain an add button in the file list header panel

### 要件 2: 音声プレーヤーの波形表示（Waveform Display）

**ユーザーストーリー:** ユーザーとして、音声プレーヤーのスライダーの代わりに波形表示を見たい。波形の中で現在の再生位置がわかるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN an audio file is loaded, THE Waveform_Display SHALL render the audio waveform by reading sample data from the audio file
2. THE Waveform_Display SHALL replace the existing Slider control in the Audio_Player
3. THE Waveform_Display SHALL visually indicate the current playback position by differentiating the played portion from the unplayed portion using distinct colors or opacity
4. WHEN a user clicks on the Waveform_Display, THE Audio_Player SHALL seek to the corresponding time position
5. WHEN a user drags on the Waveform_Display, THE Audio_Player SHALL update the playback position to follow the drag gesture
6. WHILE audio is playing, THE Waveform_Display SHALL update the playback position indicator in real time
7. THE Waveform_Display SHALL display the current time and total duration alongside the waveform
8. THE Waveform_Display on macOS SHALL be implemented as a SwiftUI View using AVAudioFile sample data
9. THE Waveform_Display on Windows SHALL be implemented as a WinUI 3 control using NAudio or equivalent library for sample data extraction

### 要件 3: 既存スペクトラム表示の置き換え

**ユーザーストーリー:** 開発者として、既存のスペクトラムバー表示（AudioSpectrumView）を波形表示に統合したい。波形表示が再生位置を示す役割を担うため、スペクトラムバーは不要になる。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL remove the existing AudioSpectrumView (macOS) and SpectrumPanel (Windows) from the audio transcription section
2. THE Waveform_Display SHALL serve as the replacement for both the Slider and the spectrum visualization

### 要件 4: 「文字起こし＋要約」処理中のGUI操作無効化

**ユーザーストーリー:** ユーザーとして、「文字起こし＋要約」処理中に誤ってボタンを押したりファイルを変更したりすることを防ぎたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE the Processing_State is active due to transcription-and-summarization, THE App SHALL disable all GUI_Controls except the status bar and section collapse/expand toggles
2. WHILE the Processing_State is active due to transcription-and-summarization, THE App SHALL disable the toolbar record button, settings button, and file picker button
3. WHILE the Processing_State is active due to transcription-and-summarization, THE App SHALL disable the FileDropZone drag-and-drop functionality
4. WHILE the Processing_State is active due to transcription-and-summarization, THE App SHALL disable the audio source Picker, transcription language Picker, and Bedrock model Picker
5. WHILE the Processing_State is active due to transcription-and-summarization, THE App SHALL display a visual indicator (reduced opacity or grayed-out appearance) on disabled controls

### 要件 5: 「ファイルから要約」処理中のGUI操作無効化

**ユーザーストーリー:** ユーザーとして、「ファイルから要約」処理中に他の操作を行えないようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE the Processing_State is active due to summarize-from-file, THE App SHALL disable all GUI_Controls except the status bar and section collapse/expand toggles
2. WHILE the Processing_State is active due to summarize-from-file, THE App SHALL disable the toolbar record button, settings button, and file picker button
3. WHILE the Processing_State is active due to summarize-from-file, THE App SHALL disable the FileDropZone drag-and-drop functionality
4. WHILE the Processing_State is active due to summarize-from-file, THE App SHALL display a visual indicator (reduced opacity or grayed-out appearance) on disabled controls

### 要件 6: 「要約」処理中のGUI操作無効化

**ユーザーストーリー:** ユーザーとして、「要約」ボタンによる再要約処理中に他の操作を行えないようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE the Processing_State is active due to re-summarization, THE App SHALL disable all GUI_Controls except the status bar and section collapse/expand toggles
2. WHILE the Processing_State is active due to re-summarization, THE App SHALL disable the toolbar record button, settings button, and file picker button
3. WHILE the Processing_State is active due to re-summarization, THE App SHALL disable the FileDropZone drag-and-drop functionality
4. WHILE the Processing_State is active due to re-summarization, THE App SHALL display a visual indicator (reduced opacity or grayed-out appearance) on disabled controls

### 要件 7: クロスプラットフォーム対応

**ユーザーストーリー:** 開発者として、上記すべての改善をmacOS版とWindows版の両方に実装したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App on macOS SHALL implement all requirements (1 through 6) using SwiftUI
2. THE App on Windows SHALL implement all requirements (1 through 6) using WinUI 3 / XAML
3. THE Waveform_Display on macOS SHALL use AVFoundation (AVAudioFile) for reading audio sample data
4. THE Waveform_Display on Windows SHALL use NAudio or an equivalent library for reading audio sample data
5. THE GUI disable behavior on macOS and Windows SHALL produce equivalent user experience
