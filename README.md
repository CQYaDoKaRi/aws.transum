# AudioTranscriptionSummary

音声文字起こし・要約・リアルタイム翻訳アプリケーション（macOS / Windows 対応）

## プロジェクト構成

```
├── macos/          # macOS 版（SwiftUI / Swift）
├── windows/        # Windows 版（WinUI 3 / C# .NET 8）
├── specs/          # 仕様書（macOS / Windows 別）
│   ├── macos/      # macOS 版仕様
│   └── windows/    # Windows 版仕様
├── docs/           # 共通ドキュメント
└── README.md
```

## 機能

- 音声ファイル読み込み（m4a, wav, mp3, aiff, mp4, mov, m4v）
- システム音声・マイクのリアルタイムキャプチャ
- Amazon Transcribe Streaming によるリアルタイム文字起こし（言語自動判別）
- Amazon Transcribe バッチ文字起こし
- Amazon Translate による翻訳（7言語: 日本語・英語・中国語・韓国語・フランス語・ドイツ語・スペイン語）
- 抽出型テキスト要約
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能（色付きExpanderヘッダー、FontIconアイコン付き）
- テキストエリアにBorderフレーム
- 設定連動（リアルタイム機能の有効/無効）
- CPU・メモリ使用状況のリアルタイム表示（全幅ステータスバー）
- 結果の自動エクスポート（エクスポート保存先設定時）

## OS 別の詳細

- [macOS 版](macos/README.md)
- [Windows 版](windows/README.md)

## Windows 版のビルド

### 前提条件

- .NET 8 SDK
- Visual Studio 2022 Community（Windows アプリケーション開発ワークロード）
- Windows App Runtime 1.6

### ビルド手順

```bash
# VS Community の MSBuild でビルド
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  windows/AudioTranscriptionSummary/AudioTranscriptionSummary.csproj `
  /p:Configuration=Release /p:Platform=x64 /restore
```

### インストーラーのビルド

Inno Setup 6 を使用してWindowsインストーラーを作成できます。

```bash
# Inno Setup 6 が必要
# ビルドスクリプトを実行
powershell -File windows/installer/build-installer.ps1
```

出力: `windows/installer/output/AudioTranscriptionSummary_Setup_1.0.0.exe`

### 実行

```bash
windows\AudioTranscriptionSummary\bin\x64\Release\net8.0-windows10.0.19041.0\AudioTranscriptionSummary.exe
```

## macOS 版のビルド

```bash
cd macos
swift build
```

## 仕様書

各プラットフォームの仕様書は `specs/` フォルダに配置:

| 仕様 | macOS | Windows |
|------|-------|---------|
| 音声文字起こし・要約 | specs/macos/audio-transcription-summary/ | specs/windows/audio-transcription-summary/ |
| Amazon Transcribe連携 | specs/macos/amazon-transcribe-integration/ | specs/windows/amazon-transcribe-integration/ |
| リアルタイム文字起こし・翻訳 | specs/macos/realtime-transcription-translation/ | specs/windows/realtime-transcription-translation/ |
