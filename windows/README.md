# AudioTranscriptionSummary - Windows 版

Windows 向け音声文字起こし・要約・リアルタイム翻訳アプリケーション（WinUI 3 / .NET 8 / C#）

## 動作環境

- Windows 10 version 1809 以降 / Windows 11
- Visual Studio 2022 (17.8+) + Windows App SDK ワークロード
- .NET 8 SDK
- AWS アカウント（Transcribe Streaming / Translate / Bedrock / S3）

## 機能

- 音声ファイル読み込み（m4a, wav, mp3, aiff, mp4, mov, m4v）
- WASAPI によるシステム音声・マイクキャプチャ
- 画面録画（動画＋音声）
- Amazon Transcribe Streaming リアルタイム文字起こし（言語自動判別）
- 文字起こし言語選択（21言語＋自動判別）
- Amazon Translate リアルタイム翻訳（7言語）
- リアルタイム自動翻訳（FinalTranscript受信時に全文翻訳をトリガー）
- Amazon Bedrock（Claude 4.x / 3.x / Titan）による生成型要約
  - Cross-Region inference profile 対応（BedrockModel.GetInferenceId）
  - 設定画面で基盤モデルを選択可能（デフォルト: Claude Sonnet 4.6）
  - 追加プロンプトで要約の指示をカスタマイズ可能（複数行入力対応）
  - 要約のみ再実行可能
  - ファイルから直接要約可能
- エラーログ（ErrorLogger: yyyyMMdd_HHmmss.error.log に詳細情報を記録）
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能（Expander）
- 折りたたみセクション自動開閉連動（録音開始/停止、ファイル選択に応じて自動制御）
- カスタムアプリアイコン（波形＋ドキュメント＋Tデザイン、タイトルバー＋タスクバー表示）
- CPU・メモリ使用状況リアルタイム表示

## ファイル命名規則

| ファイル種別 | 命名規則 |
|------------|---------|
| 録音ファイル | `yyyyMMdd_HHmmss.wav` |
| 文字起こし | `{音声ファイル名}.transcript.txt` |
| 要約 | `{音声ファイル名}.summary.txt` |
| ファイルから要約 | `{読み込みファイル名}.summary.txt` |
| エラーログ | `yyyyMMdd_HHmmss.error.log` |

## プロジェクト構造

```
windows/AudioTranscriptionSummary/
├── Models/
│   ├── AppError.cs
│   ├── AppSettings.cs
│   ├── AudioFile.cs
│   ├── AudioSourceInfo.cs
│   ├── BedrockModel.cs
│   ├── Summary.cs
│   ├── Transcript.cs
│   ├── TranscriptionLanguage.cs
│   └── TranslationLanguage.cs
├── Services/
│   ├── AppIconGenerator.cs
│   ├── AudioBufferConverter.cs
│   ├── AudioCaptureService.cs
│   ├── AudioPlayerService.cs
│   ├── ErrorLogger.cs
│   ├── ExportManager.cs
│   ├── FileImporter.cs
│   ├── RealtimeTranscribeClient.cs
│   ├── S3Service.cs
│   ├── SettingsStore.cs
│   ├── StatusMonitor.cs
│   ├── Summarizer.cs
│   ├── TranscribeClient.cs
│   └── TranslateService.cs
├── ViewModels/
│   ├── MainViewModel.cs
│   ├── RealtimeTranscriptionViewModel.cs
│   └── TranslationViewModel.cs
├── Views/
│   ├── AudioPlayerControl.xaml
│   ├── AudioPlayerControl.xaml.cs
│   ├── MainPage.xaml
│   └── MainPage.xaml.cs
└── AudioTranscriptionSummary.csproj
```

## 依存パッケージ

| パッケージ | 用途 |
|-----------|------|
| AWSSDK.TranscribeService | バッチ文字起こし |
| AWSSDK.TranscribeStreaming | リアルタイム文字起こし |
| AWSSDK.Translate | リアルタイム翻訳 |
| AWSSDK.BedrockRuntime | Bedrock 要約 |
| AWSSDK.S3 | S3 連携 |
| NAudio | 音声キャプチャ・再生 |
| CommunityToolkit.Mvvm | MVVM パターン |

## ビルド

```powershell
# VS Community MSBuild を使用（WinUI 3 の PRI タスクに必要）
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" windows/AudioTranscriptionSummary/AudioTranscriptionSummary.csproj /p:Configuration=Release /p:Platform=x64 /restore
```

> **注意**: `dotnet build` は WinUI 3 の PRI タスク DLL が見つからないため使用できません。VS Community MSBuild を使用してください。

## テスト

```powershell
# テストプロジェクトのビルド（MSBuild）
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" test/windows/AudioTranscriptionSummary.Tests/AudioTranscriptionSummary.Tests.csproj /p:Configuration=Release /p:Platform=x64 /restore

# テスト実行
dotnet test test/windows/AudioTranscriptionSummary.Tests/AudioTranscriptionSummary.Tests.csproj --no-build --configuration Release -p:Platform=x64
```

テスト内容:
- ErrorLogger テスト（5件）: エラーログ出力、ファイル名ベース/app.error.log、追記、テストデータ存在確認
- AdditionalPromptPersistence テスト（3件）: 追加プロンプトの保存・復元、空文字、他設定への副作用なし

## インストーラー

```powershell
# Inno Setup 6 が必要
cd windows/installer
.\build-installer.ps1
# 出力: windows/installer/output/AudioTranscriptionSummary_Setup_1.0.0.exe
```
