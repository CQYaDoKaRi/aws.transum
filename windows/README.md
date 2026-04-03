# AudioTranscriptionSummary - Windows 版

Windows 向け音声文字起こし・要約アプリケーション（WinUI 3 / .NET 8 / C#）

## 技術スタック

- WinUI 3 (Windows App SDK)
- .NET 8
- C#
- MVVM パターン（CommunityToolkit.Mvvm）
- AWS SDK for .NET（Amazon Transcribe Streaming, Amazon Translate, Amazon S3）

## 前提条件

- Windows 10 version 1809 以降 / Windows 11
- Visual Studio 2022 (17.8+) + Windows App SDK ワークロード
- .NET 8 SDK

## プロジェクト構成

```
windows/
├── AudioTranscriptionSummary.sln
├── AudioTranscriptionSummary/
│   ├── App.xaml / App.xaml.cs
│   ├── MainWindow.xaml / MainWindow.xaml.cs
│   ├── Models/
│   │   ├── AudioFile.cs
│   │   ├── Transcript.cs
│   │   ├── Summary.cs
│   │   ├── TranslationLanguage.cs
│   │   └── AppSettings.cs
│   ├── Services/
│   │   ├── AudioCaptureService.cs        # WASAPI による音声キャプチャ
│   │   ├── RealtimeTranscribeClient.cs   # Amazon Transcribe Streaming
│   │   ├── TranslateService.cs           # Amazon Translate
│   │   ├── TranscribeService.cs          # Amazon Transcribe (バッチ)
│   │   ├── S3Service.cs                  # Amazon S3
│   │   ├── AudioPlayerService.cs         # 音声再生
│   │   └── SettingsStore.cs              # 設定永続化
│   ├── ViewModels/
│   │   ├── MainViewModel.cs
│   │   ├── RealtimeTranscriptionViewModel.cs
│   │   └── SettingsViewModel.cs
│   └── Views/
│       ├── MainPage.xaml                 # メインレイアウト（左右分割）
│       ├── FileDropZone.xaml             # ファイル読み込みエリア
│       ├── AudioCaptureControl.xaml      # 録音コントロール
│       ├── TranscriptionPreviewPanel.xaml # リアルタイム文字起こし
│       ├── TranslationPanel.xaml         # 翻訳結果
│       ├── SummaryPanel.xaml             # 要約結果
│       ├── AudioPlayerControl.xaml       # 音声プレーヤー
│       └── SettingsDialog.xaml           # 設定画面
└── AudioTranscriptionSummary.Tests/
    └── ...
```

## macOS 版との共通点

- 同じ UI レイアウト（左右分割、右パネル3セクション）
- 同じ操作フロー（録音→文字起こし→翻訳→要約→エクスポート）
- 同じ AWS サービス連携（Transcribe Streaming, Translate, S3）
- 同じファイル命名規則（日付_時刻.拡張子）
- 共通の仕様書（../specs/）

## macOS 版との相違点

| 機能 | macOS | Windows |
|------|-------|---------|
| UI フレームワーク | SwiftUI | WinUI 3 (XAML) |
| 音声キャプチャ | ScreenCaptureKit / AVCaptureSession | WASAPI / Windows.Media.Capture |
| 音声再生 | AVAudioPlayer | MediaPlayer / NAudio |
| 設定保存 | ~/Library/Application Support/ | %APPDATA%/ |
| AWS SDK | AWS SDK for Swift | AWS SDK for .NET |
