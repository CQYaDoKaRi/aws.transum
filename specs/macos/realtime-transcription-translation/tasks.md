# 実装計画: リアルタイム文字起こし・翻訳機能

## タスク

- [x] 1. AWS SDK 依存関係追加（AWSTranscribeStreaming, AWSTranslate）
- [x] 2. TranslationLanguage モデル + AudioBufferConverter
- [x] 3. RealtimeTranscribeClient + TranslateService
- [x] 4. RealtimeTranscriptionViewModel + TranslationViewModel
- [x] 5. SystemAudioCapture 音声バッファ転送
- [x] 6. UI: TranscriptionPreviewPanel, TranslationPanel, CopyableTextView
- [x] 7. MainView レイアウト（上下分割、全セクション折りたたみ可能）
- [x] 8. 設定連動（リアルタイム有効/無効でセクション表示/非表示）
- [x] 9. ツールバー統合（録音/停止/キャンセル + 音源選択連動）
- [x] 10. 画面録画を音源選択 Picker に統合（動画＋音声固定）
- [x] 11. 不要コード削除（RecordingMode, screenRecordingSaveMode）
- [x] 12. ドキュメント更新
- [x] 13. Windows 版更新
