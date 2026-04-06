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
- Amazon Translate リアルタイム翻訳（7言語）
- Amazon Bedrock（Claude 4.x / 3.x / Titan）による生成型要約
  - 設定画面で基盤モデルを選択可能（デフォルト: Claude Sonnet 4.6）
  - 追加プロンプトで要約の指示をカスタマイズ可能（複数行入力対応）
  - 要約のみ再実行可能
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能（Expander）
- 折りたたみセクション自動開閉連動（録音開始/停止、ファイル選択に応じて自動制御）
- CPU・メモリ使用状況リアルタイム表示

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
cd windows\AudioTranscriptionSummary
dotnet build -c Release -p:Platform=x64
```
