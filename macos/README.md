# AudioTranscriptionSummary - macOS 版

macOS 向け音声文字起こし・要約・リアルタイム翻訳アプリケーション（SwiftUI）

## 動作環境

- macOS 14（Sonoma）以降
- Xcode 16 以降 / Swift 6.0 以降
- AWS アカウント（Transcribe Streaming / Translate / S3）

## 機能

- 音声ファイル読み込み（m4a, wav, mp3, aiff, mp4, mov, m4v）
- システム音声・マイク・特定アプリのリアルタイムキャプチャ（1分分割録音対応）
- 画面録画（動画＋音声、音源選択 Picker に統合）
- Amazon Transcribe Streaming リアルタイム文字起こし（言語自動判定 / 指定言語切り替え、ストリーミング中の言語変更対応）
- Amazon Transcribe バッチ文字起こし（言語自動判別対応、複数ファイル一括文字起こし対応）
- Amazon Translate リアルタイム翻訳（7言語: ja, en, zh, ko, fr, de, es）
- テキスト要約 + 翻訳
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能
- 折りたたみセクション自動開閉連動（録音開始/停止、ファイル選択に応じて自動制御）
- 録音中の UI 制御（設定ボタン・入力ソース・分割時間・ファイル操作・要約ファイルボタン無効化）
- 録音経過時間のステータスバー表示
- リアルタイム文字起こしの有効/無効切り替え（録音中でも切り替え可能、ストリーム出力ファイルへの追記対応）
- 設定の永続化（ファイル分割時間・リアルタイム ON/OFF を settings.json に保存・復元）
- 設定画面の即反映（変更時に即座に保存・アプリに反映）
- 二重起動防止（NSRunningApplication による同一バンドル ID 検出）
- 起動時 AWS 接続テスト（失敗時に設定画面を自動表示）
- 設定画面にステータスバー（接続ステータス・エラーメッセージ表示）
- カスタムアプリアイコン（波形＋ドキュメント＋Tデザイン、Dock表示）
- SSO 認証情報のファイルキャッシュ（有効期限内はアプリ再起動時に自動復元）
- 設定連動（リアルタイム機能の有効/無効）
- CPU・メモリ使用状況リアルタイム表示

## UI レイアウト

```
[ツールバー: 録音/停止 | キャンセル | 設定]
▼ 入力（音源選択 + リアルタイム文字起こしトグル + レベルメーター）
▼ リアルタイム文字起こし（言語選択 + 再判別） | 翻訳
▼ 音声文字起こし（ファイル選択 + プレーヤー + 言語選択 + 結果） | 翻訳
▼ 要約（基盤モデル選択 + プロンプト） | 翻訳
[ステータスバー: 録音中 MM:SS | CPU アプリ/全体 | メモリ]
```

## ビルド・実行

```bash
cd macos
swift build
swift run AudioTranscriptionSummary
```

## インストーラー作成

```bash
cd macos
bash installer/build-app.sh
```

出力:
- `macos/installer/output/AudioTranscriptionSummary.app` — .app バンドル
- `macos/installer/output/AudioTranscriptionSummary_1.0.0.dmg` — DMG インストーラー

インストール: DMG を開いて .app を Applications フォルダにドラッグ

## テスト

```bash
cd macos
swift test
```
