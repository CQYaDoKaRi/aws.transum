# AudioTranscriptionSummary - Windows版

WinUI 3 / .NET 8 ネイティブアプリケーション

## 技術スタック

| 技術 | 用途 |
|------|------|
| WinUI 3 (Windows App SDK 1.6) | UI フレームワーク |
| .NET 8 | ランタイム |
| CommunityToolkit.Mvvm | MVVM パターン |
| NAudio | 音声キャプチャ・再生 |
| AWSSDK.TranscribeService 4.* | Amazon Transcribe |
| AWSSDK.TranscribeStreaming 4.* | Amazon Transcribe Streaming |
| AWSSDK.Translate 4.* | Amazon Translate |
| AWSSDK.S3 4.* | S3 アップロード |

## プロジェクト構成

```
windows/AudioTranscriptionSummary/
├── Models/
│   ├── AppError.cs          # エラー型
│   ├── AppSettings.cs       # 設定モデル
│   ├── AudioFile.cs         # 音声ファイルモデル
│   ├── AudioSourceInfo.cs   # 音源情報モデル
│   ├── Summary.cs           # 要約モデル
│   ├── Transcript.cs        # 文字起こしモデル
│   └── TranslationLanguage.cs # 翻訳言語列挙型
├── Services/
│   ├── AudioBufferConverter.cs    # 音声バッファ変換（PCM 16kHz）
│   ├── AudioCaptureService.cs     # 音声キャプチャ（NAudio）
│   ├── AudioPlayerService.cs      # 音声再生（NAudio）
│   ├── ExportManager.cs           # エクスポート
│   ├── FileImporter.cs            # ファイル読み込み
│   ├── RealtimeTranscribeClient.cs # リアルタイム文字起こし（Transcribe Streaming）
│   ├── S3Service.cs               # S3アップロード/削除
│   ├── SettingsStore.cs           # 設定永続化（JSON）
│   ├── StatusMonitor.cs           # CPU/メモリ監視
│   ├── Summarizer.cs              # 抽出型要約
│   ├── TranscribeClient.cs        # バッチ文字起こし（Transcribe）
│   └── TranslateService.cs        # 翻訳（Translate）
├── ViewModels/
│   ├── MainViewModel.cs                  # メインViewModel
│   ├── RealtimeTranscriptionViewModel.cs # リアルタイム文字起こしViewModel
│   └── TranslationViewModel.cs           # 翻訳ViewModel
├── Views/
│   ├── MainPage.xaml(.cs)      # メイン画面
│   └── AudioPlayerControl.xaml(.cs) # 音声プレーヤー
├── App.xaml(.cs)               # アプリケーションエントリ
├── MainWindow.xaml(.cs)        # メインウィンドウ
└── AudioTranscriptionSummary.csproj
```

## ビルド

```bash
& "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe" `
  AudioTranscriptionSummary.csproj /p:Configuration=Release /p:Platform=x64 /restore
```

## 設定

アプリ内の設定ボタンから以下を構成:
- AWS 認証情報（Access Key ID, Secret Access Key）
- AWS リージョン、S3 バケット名
- 録音保存先、エクスポート保存先
- リアルタイム文字起こし有効/無効
- 言語自動判別有効/無効

設定は `%APPDATA%\AudioTranscriptionSummary\settings.json` に保存されます。

## インストーラー

Inno Setup 6 を使用してWindowsインストーラーを作成できます。

### 前提条件

- [Inno Setup 6](https://jrsoftware.org/isinfo.php) がインストール済みであること
- Release ビルドが完了していること

### ビルド手順

```bash
# ビルドスクリプトを実行
powershell -File installer/build-installer.ps1
```

または Inno Setup Compiler で直接コンパイル:

```bash
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer/setup.iss
```

### 出力

- `installer/output/AudioTranscriptionSummary_Setup_1.0.0.exe`
- 日本語・英語対応
- デスクトップアイコン作成オプション付き
