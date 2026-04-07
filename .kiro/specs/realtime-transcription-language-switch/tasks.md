# 実装計画: リアルタイム文字起こし言語切り替え

## 概要

リアルタイム文字起こし機能に言語選択（言語自動判定/指定言語）、ストリーミング中の言語切り替え、リアルタイムトグル、基盤モデル選択のメイン画面配置を追加する。macOS / Windows 両対応。

## タスク

- [x] 1. テスト基盤の作成
  - [x] 1.1 `RealtimeTranscribing` プロトコルを作成する
  - [x] 1.2 `MockRealtimeTranscribeClient` を作成する
  - [x] 1.3 `RealtimeTranscribeClient` をプロトコルに準拠させる

- [x] 2. RealtimeTranscriptionViewModel の言語設定対応
  - [x] 2.1 `selectedLanguage: TranscriptionLanguage = .auto` プロパティを追加
  - [x] 2.2 `startStreamingInternal()` を `selectedLanguage` に基づいて分岐
  - [x] 2.3 `restartStreamingWithNewLanguage()` メソッドを実装
  - [x] 2.4 リアルタイム翻訳条件を修正（指定言語/検出言語と翻訳先言語の比較）
  - [x] 2.5 `transcribeClient` の型を `RealtimeTranscribing` プロトコルに変更（DI 対応）

- [x] 3. TranscriptionPreviewPanel の言語セレクタ UI
  - [x] 3.1 言語 Picker（`TranscriptionLanguage.allCases`、ラベルなし、左寄せ）
  - [x] 3.2 自動検出時の検出言語ラベル + 再判別ボタン（緑色アイコン）
  - [x] 3.3 `onChange(of: selectedLanguage)` で再接続

- [x] 4. MainView の UI 変更
  - [x] 4.1 入力グループにリアルタイム文字起こしトグルを追加（音声ソースの隣）
  - [x] 4.2 要約セクションに基盤モデル Picker を追加（ラベルなし、左寄せ、要約中は無効）
  - [x] 4.3 設定画面からリアルタイム設定・要約設定を削除

- [x] 5. TranscriptionLanguage の表示名変更
  - [x] 5.1 `auto` の `displayName` を「言語自動判定」に変更（macOS / Windows 共通）

- [x] 6. 音声文字起こしの言語 Picker 統一
  - [x] 6.1 TranscriptView の言語 Picker からラベルを削除、左寄せ、幅統一

- [x] 7. Windows 版対応
  - [x] 7.1 `RealtimeTranscriptionViewModel` に `SelectedRealtimeLanguage` プロパティ追加
  - [x] 7.2 `MainPage.xaml` にリアルタイム言語 ComboBox、トグル、基盤モデル ComboBox 追加
  - [x] 7.3 `MainViewModel` に `RestartRealtimeStreamingAsync()` 追加
  - [x] 7.4 設定画面からリアルタイム設定・要約設定を削除
  - [x] 7.5 リアルタイム翻訳条件を修正

- [x] 8. テスト更新
  - [x] 8.1 `ModelsTests` の `fr-FR` テストを修正
  - [x] 8.2 `auto` の `displayName` テストを追加
  - [x] 8.3 `selectedLanguage` デフォルト値テストを追加
