# AudioTranscriptionSummary - macOS 版

macOS 向け音声文字起こし・要約・リアルタイム翻訳アプリケーション（SwiftUI）

## 動作環境

- macOS 14（Sonoma）以降
- Xcode 16 以降 / Swift 6.0 以降
- AWS アカウント（Transcribe Streaming / Translate / S3）

## 機能

- 音声ファイル読み込み（m4a, wav, mp3, aiff, mp4, mov, m4v）
- システム音声・マイク・特定アプリのリアルタイムキャプチャ
- 画面録画（動画＋音声、音源選択 Picker に統合）
- Amazon Transcribe Streaming リアルタイム文字起こし（言語自動判定 / 指定言語切り替え、ストリーミング中の言語変更対応）
- Amazon Transcribe バッチ文字起こし（言語自動判別対応）
- Amazon Translate リアルタイム翻訳（7言語: ja, en, zh, ko, fr, de, es）
- テキスト要約 + 翻訳
- 全テキストエリアにコピーボタン
- 全セクション折りたたみ可能
- 折りたたみセクション自動開閉連動（録音開始/停止、ファイル選択に応じて自動制御）
- カスタムアプリアイコン（波形＋ドキュメント＋Tデザイン、Dock表示）
- 設定連動（リアルタイム機能の有効/無効）
- CPU・メモリ使用状況リアルタイム表示

## UI レイアウト

```
[ツールバー: 録音/停止 | キャンセル | 設定]
▼ 入力（音源選択 + リアルタイム文字起こしトグル + レベルメーター）
▼ リアルタイム文字起こし（言語選択 + 再判別） | 翻訳
▼ 音声文字起こし（ファイル選択 + プレーヤー + 言語選択 + 結果） | 翻訳
▼ 要約（基盤モデル選択 + プロンプト） | 翻訳
[ステータスバー: CPU アプリ/全体 | メモリ]
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
