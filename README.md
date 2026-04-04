# AudioTranscriptionSummary

音声文字起こし・要約・リアルタイム翻訳アプリケーション（macOS / Windows 対応）

## プロジェクト構成

```
├── macos/          # macOS 版（SwiftUI / Swift）
├── windows/        # Windows 版（WinUI 3 / C# .NET 8）
├── specs/          # 共通仕様書（macOS / Windows）
├── docs/           # 共通ドキュメント（UI レイアウト設計書）
└── README.md
```

## 機能

- 音声ファイル読み込み（m4a, wav, mp3, aiff, mp4, mov, m4v）
- システム音声・マイク・特定アプリのリアルタイムキャプチャ
- 画面録画（動画＋音声）
- Amazon Transcribe Streaming リアルタイム文字起こし（言語自動判別）
- Amazon Translate リアルタイム翻訳（7言語）
- テキスト要約 + 翻訳
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能
- CPU・メモリ使用状況リアルタイム表示

## OS 別の詳細

- [macOS 版](macos/README.md)
- [Windows 版](windows/README.md)
- [共通 UI レイアウト設計書](docs/ui-layout-spec.md)
