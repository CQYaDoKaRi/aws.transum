# AudioTranscriptionSummary - macOS 版

macOS 向け音声文字起こし・要約・リアルタイム翻訳アプリケーション（SwiftUI）

## 動作環境

- macOS 14（Sonoma）以降
- Xcode 16 以降
- Swift 6.0 以降
- AWS アカウント（Transcribe Streaming / Translate / S3）

## ビルド・実行

```bash
cd macos
swift build
swift run AudioTranscriptionSummary
```

## テスト

```bash
cd macos
swift test
```

## 詳細

共通 UI レイアウト設計書: [docs/ui-layout-spec.md](../docs/ui-layout-spec.md)
