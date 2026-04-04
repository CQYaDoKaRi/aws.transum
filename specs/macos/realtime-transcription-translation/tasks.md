# 実装計画: リアルタイム文字起こし・翻訳機能（macOS）

## タスク

- [x] 1. AWS SDK 依存関係追加（AWSTranscribeStreaming, AWSTranslate）
- [x] 2. TranslationLanguage モデル + AudioBufferConverter
- [x] 3. RealtimeTranscribeClient + TranslateService
- [x] 4. RealtimeTranscriptionViewModel + TranslationViewModel
- [x] 5. SystemAudioCapture 音声バッファ転送
- [x] 6. UI: TranscriptionPreviewPanel, TranslationPanel, CopyableTextView
- [x] 7. MainView レイアウト（上下分割、全セクション折りたたみ可能）
- [x] 8. 設定連動（リアルタイム有効/無効でセクション表示/非表示）
- [x] 9. ツールバー統合（録音/停止/キャンセル右寄せ、設定右端）
- [x] 10. 画面録画を音源選択 Picker に統合（動画＋音声固定）
- [x] 11. 不要コード削除（RecordingMode, screenRecordingSaveMode）
- [x] 12. 翻訳パネル: コピーボタンを言語選択と同一ライン右寄せ
- [x] 13. テキストエリア: ウィンドウサイズ自動フィット + スクロールバー
- [x] 14. ファイル選択: 点線枠統一、コンパクトレイアウト
- [x] 15. プレーヤー: 音声文字起こしグループ内に移動（常時表示）
- [x] 16. 設定画面: Form→VStack書き換え（TextField入力可能化）
- [x] 17. 設定画面: ラベル左寄せ150px統一、squareBorder+focusable
- [x] 18. エクスポートボタン削除（自動保存のため不要）
- [x] 19. 初回起動エラー修正（モニタリング中のcaptureDidFail無視）
- [x] 20. 文字起こし言語に「自動」追加（identifyLanguage対応）
- [x] 21. ステータスバー: CPU アプリ→全体の順、メモリ%表示
- [x] 22. 入力ソース順序: 画面録画→システム全体（デフォルト）→マイク→アプリ
- [x] 23. ドキュメント更新 + git push
