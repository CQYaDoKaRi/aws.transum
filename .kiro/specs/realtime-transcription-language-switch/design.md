# 技術設計ドキュメント（Design Document）

## 概要（Overview）

リアルタイム文字起こし機能における言語切り替え、リアルタイムトグル、基盤モデル選択のメイン画面配置の技術設計。

### 実装方針

- `LanguageMode` enum は使用せず、`TranscriptionLanguage`（`auto` 含む）の単一 Picker で言語選択を統合
- 自動検出時の `languageOptions` は主要5言語（ja-JP, en-US, zh-CN, ko-KR, fr-FR）に制限（Transcribe Streaming の上限対応）
- ストリーミング中の言語切り替えは再接続方式（Amazon Transcribe Streaming は接続後の言語変更不可）
- `RealtimeTranscribeClient` を `RealtimeTranscribing` プロトコルで抽象化し、DI/テスト対応
- リアルタイム文字起こしの有効/無効トグルを入力グループに配置
- 基盤モデル選択を要約セクションに配置、設定ファイルに永続化

## アーキテクチャ

```
MainView
├── 入力グループ
│   ├── 音声ソース Picker
│   └── リアルタイム文字起こしトグル ← 新規
├── リアルタイム文字起こし
│   ├── TranscriptionPreviewPanel
│   │   └── 言語 Picker（auto含む全言語） ← 変更
│   └── TranslationPanel
├── 音声文字起こし
│   └── 言語 Picker（auto含む全言語）
└── 要約
    └── 基盤モデル Picker ← 設定画面から移動
```

## コンポーネント変更

### RealtimeTranscriptionViewModel

```swift
// selectedLanguage で auto/指定言語を統合管理
@Published var selectedLanguage: TranscriptionLanguage = .auto

// 自動検出時の言語候補（Transcribe Streaming は最大5言語）
static let autoDetectLanguageOptions = ["ja-JP", "en-US", "zh-CN", "ko-KR", "fr-FR"]

// DI 対応: RealtimeTranscribing プロトコル
private let transcribeClient: RealtimeTranscribing

// ストリーミング再接続
func restartStreamingWithNewLanguage() async
```

### TranscriptionPreviewPanel

- 言語 Picker（`TranscriptionLanguage.allCases`、ラベルなし）
- 自動検出時: 検出言語ラベル + 再判別ボタン（緑色 `arrow.triangle.2.circlepath`）
- `onChange(of: selectedLanguage)` で再接続

### MainView

- 入力グループ: 音声ソース Picker の隣にリアルタイムトグル（スイッチ左、ラベル右）
- 要約セクション: 基盤モデル Picker（ラベルなし、左寄せ、要約中は無効）
- 設定画面からリアルタイム設定・要約設定を削除

### リアルタイム翻訳条件

```swift
// 指定言語モード: selectedLanguage のプレフィックスと翻訳先言語を比較
// 自動検出モード: detectedLanguage のプレフィックスと翻訳先言語を比較
// 異なる場合のみ翻訳を実行
```

## Windows 版対応

macOS 版と同等の変更を Windows（WinUI 3）版にも適用:
- `RealtimeTranscriptionViewModel` に `SelectedRealtimeLanguage` プロパティ追加
- `MainPage.xaml` にリアルタイム言語 ComboBox、リアルタイムトグル、基盤モデル ComboBox 追加
- `MainViewModel` に `RestartRealtimeStreamingAsync()` 追加
- 設定画面からリアルタイム設定・要約設定を削除
- `TranscriptionLanguage.Auto` の表示名を「言語自動判定」に変更
