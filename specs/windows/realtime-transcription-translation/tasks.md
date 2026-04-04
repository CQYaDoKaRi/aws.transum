# 実装計画: リアルタイム文字起こし・翻訳機能（Windows版）

## 概要

Amazon Transcribe Streaming APIによるリアルタイム文字起こし、Amazon Translateによる翻訳機能を実装する。NAudioのDataAvailableイベントから音声データをストリーミング送信し、WinUI 3のUIで結果を表示する。

## タスク

- [x] 1. 音声バッファ変換とストリーミングクライアント
  - [x] 1.1 AudioBufferConverter を実装する
    - NAudioのWaveFormat → PCM 16kHz 16-bit mono変換
    - WaveFormatConversionStream使用
    - _要件: 6.1, 6.2_

  - [x] 1.2 RealtimeTranscribeClient を実装する
    - AWSSDK.TranscribeService の StartStreamTranscriptionAsync
    - PCM 16kHz 16-bit LE mono送信
    - PartialTranscriptReceived / FinalTranscriptReceived イベント
    - LanguageDetected イベント
    - 言語自動判別（ja-JP, en-US）
    - 接続切断時の自動再接続（最大3回）
    - _要件: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2_

- [x] 2. 翻訳サービス
  - [x] 2.1 TranslateService を実装する
    - AWSSDK.Translate の TranslateTextAsync
    - ソース言語: "auto"
    - 指数バックオフ再試行（1s, 2s, 4s、最大3回）
    - 空テキストはAPI呼び出しなし
    - _要件: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_

- [x] 3. ViewModel
  - [x] 3.1 RealtimeTranscriptionViewModel を実装する
    - ObservableObject: FinalText, PartialText, DetectedLanguage, ErrorMessage
    - AppendFinalTranscript / UpdatePartialTranscript / ToTranscript / Reset
    - _要件: 1.3, 1.4, 1.8_

  - [x] 3.2 TranslationViewModel を更新する
    - 既存のTranslationViewModelをTranslateService連携に更新
    - TranslateAsync / Reset
    - _要件: 3.1, 3.4_

- [x] 4. AudioCaptureService にストリーミング連携を追加
  - [x] 4.1 DataAvailableイベントでRealtimeTranscribeClientに音声データを送信する
    - AudioBufferConverterで変換後にSendAudioChunk
    - 送信失敗時も録音は継続
    - _要件: 6.3, 6.4_

- [x] 5. UI実装
  - [x] 5.1 リアルタイム文字起こしパネルを実装する
    - 確定テキスト（通常スタイル）+ 暫定テキスト（グレー）
    - 自動スクロール
    - IsTextSelectionEnabled + コピーボタン
    - 言語バッジ表示
    - _要件: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x] 5.2 翻訳パネルを全セクションに実装する
    - ComboBox（言語選択）+ 翻訳ボタン + テキスト表示 + コピーボタン
    - リアルタイム / バッチ文字起こし / 要約の3箇所
    - リアルタイムは自動翻訳モード
    - _要件: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_

  - [x] 5.3 MainPage レイアウトを最終版に更新する
    - 上下分割: 入力 / 出力
    - 3つのExpanderセクション（各左右2列）
    - リアルタイムセクションの表示/非表示（設定連動）
    - ステータスバー右寄せ
    - _要件: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

- [x] 6. 録音開始時の初期化
  - [x] 6.1 録音開始時に全テキストをクリアする
    - RealtimeTranscriptionVM: Reset
    - 各TranslationVM: Reset
    - MainViewModel: Transcript=null, Summary=null, AudioFile=null
    - _要件: 10.5_

- [x] 7. 設定連動
  - [x] 7.1 リアルタイム文字起こしの有効/無効を設定に連動する
    - IsRealtimeEnabled=false → リアルタイムセクション非表示
    - IsAutoDetectEnabled → 言語自動判別の有効/無効
    - DefaultTargetLanguage → 翻訳パネルのデフォルト言語
    - _要件: 9.3, 9.4, 9.5_

- [x] 8. チェックポイント - リアルタイム文字起こし・翻訳の動作確認

## 備考

- AWSSDK.TranscribeService（Streaming API含む）とAWSSDK.Translateは既にcsprojに追加済み
- 各タスクは対応する要件番号を参照
