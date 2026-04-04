# 技術設計ドキュメント（macOS リアルタイム文字起こし・翻訳）

## アーキテクチャ

- RealtimeTranscribeClient: Transcribe Streaming API 接続
- TranslateService: Translate API（指数バックオフ再試行）
- RealtimeTranscriptionViewModel: リアルタイム文字起こし状態管理
- TranslationViewModel: 各翻訳パネル独立インスタンス（リアルタイム・文字起こし・要約）
- AudioBufferConverter: CMSampleBuffer → PCM 16-bit LE 変換

## UI レイアウト

上下分割。全セクション折りたたみ可能。各セクション左右2列（元テキスト | 翻訳）。
ツールバー: 録音/停止 → キャンセル → 設定（右端）。
入力ソース Picker に画面録画を統合。プレーヤーは音声文字起こしグループ内常時表示。
設定連動でリアルタイムセクション表示/非表示。

## 設定画面

VStack ベースレイアウト（Form/Section 不使用）。
TextField: squareBorder + focusable。onAppear で makeKey()。
ラベル: 左寄せ 150px 統一。

## エラーハンドリング

モニタリング中の captureDidFail は無視（初回起動エラー防止）。
録音中のエラーのみ errorMessage に表示。
