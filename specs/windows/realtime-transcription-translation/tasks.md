# 実装計画: リアルタイム文字起こし・翻訳・Bedrock要約（Windows）

## タスク

- [x] 1. AWS SDK 依存関係（TranscribeStreaming, Translate, BedrockRuntime, S3）
- [x] 2. モデル: TranslationLanguage, BedrockModel, AppSettings（bedrockModelId追加）
- [x] 3. サービス: RealtimeTranscribeClient, TranslateService, Summarizer（Bedrock対応）
- [x] 4. ViewModel: MainViewModel（追加プロンプト、要約し直し）, RealtimeTranscriptionViewModel, TranslationViewModel
- [x] 5. UI: MainPage.xaml（全セクション折りたたみ、プロンプト入力、要約し直しボタン）
- [x] 6. 設定画面: 基盤モデル選択、リアルタイム設定
- [x] 7. ドキュメント更新
