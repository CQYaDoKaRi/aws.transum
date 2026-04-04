# Specs

## フォルダ構成

```
specs/
├── macos/                                  # Mac版
│   ├── audio-transcription-summary/        # 音声文字起こし・要約
│   ├── amazon-transcribe-integration/      # Amazon Transcribe連携
│   └── realtime-transcription-translation/ # リアルタイム文字起こし・翻訳
└── windows/                                # Windows版
    ├── audio-transcription-summary/        # 音声文字起こし・要約
    ├── amazon-transcribe-integration/      # Amazon Transcribe連携
    └── realtime-transcription-translation/ # リアルタイム文字起こし・翻訳
```

## プラットフォーム区分

- **macos/**: Mac版（SwiftUI、AVFoundation、ScreenCaptureKit、AWS SDK for Swift）
- **windows/**: Windows版（WinUI 3 / .NET 8、NAudio、AWS SDK for .NET）

Mac版とWindows版は同じspec構成で、各プラットフォーム固有の技術スタックに合わせた仕様を定義。
