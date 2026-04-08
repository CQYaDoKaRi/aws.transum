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
- 文字起こし言語選択（21言語＋自動判別: 日本語、英語、中国語、韓国語、フランス語、ドイツ語、スペイン語、ポルトガル語、イタリア語、ヒンディー語、アラビア語、ロシア語、トルコ語、オランダ語、スウェーデン語、ポーランド語、タイ語、インドネシア語、ベトナム語、マレー語）
- Amazon Translate リアルタイム翻訳（7言語）
- Amazon Bedrock（Claude 4.x / 3.x / Titan）による生成型要約
  - Cross-Region inference profile 対応（GetInferenceId）
  - 設定画面で基盤モデルを選択可能（デフォルト: Claude Sonnet 4.6）
  - 追加プロンプトで要約の指示をカスタマイズ可能
  - 要約のみ再実行可能
  - ファイルから直接要約可能
  - AWS 未設定時はローカル抽出型要約にフォールバック
- エラーログ（ErrorLogger: yyyyMMdd_HHmmss.error.log に詳細情報を記録）
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能
- 折りたたみセクション自動開閉連動（録音開始/停止、ファイル選択に応じて自動制御）
- 録音中の UI 制御（設定ボタン・入力ソース・分割時間・ファイル操作・要約ファイルボタン無効化）
- 録音経過時間のステータスバー表示
- リアルタイム文字起こしの有効/無効切り替え（録音中でも切り替え可能、ストリーム出力ファイルへの追記対応）
- 設定の永続化（ファイル分割時間・リアルタイム ON/OFF を settings.json に保存・復元）
- 設定画面の即反映（変更時に即座に保存・アプリに反映）
- 二重起動防止（macOS: NSRunningApplication / Windows: Mutex）
- 起動時 AWS 接続テスト（失敗時に設定画面を自動表示）
- 設定画面にステータスバー（接続ステータス・エラーメッセージ表示）
- カスタムアプリアイコン（波形＋ドキュメント＋Tデザイン）
- SSO 認証情報のファイルキャッシュ（アプリ再起動時に自動復元）
- CPU・メモリ使用状況リアルタイム表示

## OS 別の詳細

- [macOS 版](macos/README.md)
- [Windows 版](windows/README.md)
- [共通 UI レイアウト設計書](docs/ui-layout-spec.md)

## インストーラー

| OS | コマンド | 出力 |
|----|---------|------|
| macOS | `bash macos/installer/build-app.sh` | `macos/installer/output/AudioTranscriptionSummary_1.0.0.dmg` |
| Windows | `powershell windows/installer/build-installer.ps1` | `windows/installer/output/AudioTranscriptionSummary_Setup_1.0.0.exe` |

## テスト

| OS | ビルド | 実行 |
|----|--------|------|
| macOS | `cd macos && swift build` | `cd macos && swift test` |
| Windows | `MSBuild test/windows/AudioTranscriptionSummary.Tests/AudioTranscriptionSummary.Tests.csproj /p:Configuration=Release /p:Platform=x64 /restore` | `dotnet test test/windows/AudioTranscriptionSummary.Tests/ --no-build -c Release -p:Platform=x64` |
