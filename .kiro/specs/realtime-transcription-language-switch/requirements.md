# 要件定義（Requirements）

## はじめに

リアルタイム文字起こし機能において、文字起こし言語を「言語自動判定」と「指定言語」で切り替えられるようにする。さらに、リアルタイム文字起こしストリーミング中でも言語設定を変更し、新しい設定で即座にストリーミングを再開できるようにする。また、リアルタイム文字起こしの有効/無効をメイン画面の入力グループから直接切り替えられるようにし、要約の基盤モデル選択もメイン画面に配置する。

## 用語集（Glossary）

- **Language_Picker**: リアルタイム文字起こしの言語を選択する Picker（`TranscriptionLanguage` enum の全値を表示）
- **Realtime_Transcription_ViewModel**: リアルタイム文字起こしの状態管理を担当する ViewModel（`RealtimeTranscriptionViewModel`）
- **Realtime_Transcribe_Client**: Amazon Transcribe Streaming API との接続を管理するクライアント（`RealtimeTranscribeClient`）
- **Streaming_Session**: Amazon Transcribe Streaming API との1回の接続セッション
- **Transcription_Language**: Amazon Transcribe がサポートする文字起こし言語（`TranscriptionLanguage` enum、`auto` 含む）

## 要件（Requirements）

### 要件 1: 言語選択

**ユーザーストーリー:** ユーザーとして、リアルタイム文字起こしの言語を「言語自動判定」と「指定言語」で切り替えたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Language_Picker SHALL `TranscriptionLanguage` enum の全値（`auto` 含む）を選択肢として提供する
2. WHEN `auto`（言語自動判定）が選択された場合、THE Realtime_Transcription_ViewModel SHALL Amazon Transcribe Streaming の `identifyLanguage` 機能を使用し、主要5言語（ja-JP, en-US, zh-CN, ko-KR, fr-FR）を `languageOptions` に渡してストリーミングを開始する
3. WHEN 指定言語が選択された場合、THE Realtime_Transcription_ViewModel SHALL 選択された言語コードを `languageCode` パラメータとして使用してストリーミングを開始する
4. THE Realtime_Transcription_ViewModel SHALL `selectedLanguage` のデフォルト値として `.auto` を使用する

### 要件 2: ストリーミング中の言語切り替え

**ユーザーストーリー:** ユーザーとして、リアルタイム文字起こし中でも言語設定を変更したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE Streaming_Session が実行中の場合、THE Language_Picker SHALL 操作可能な状態を維持する
2. WHEN ストリーミング中に言語が変更された場合、THE Realtime_Transcription_ViewModel SHALL 現在の Streaming_Session を停止し、新しい言語設定で Streaming_Session を再開する
3. WHEN ストリーミングの再接続が実行される場合、THE Realtime_Transcription_ViewModel SHALL 再接続前に取得済みの確定テキスト（finalText）を保持する
4. WHEN ストリーミングの再接続が実行される場合、THE Realtime_Transcription_ViewModel SHALL 暫定テキスト（partialText）をクリアする
5. IF ストリーミングの再接続中にエラーが発生した場合、THEN THE Realtime_Transcription_ViewModel SHALL エラーメッセージを表示し、ストリーミング停止状態に遷移する

### 要件 3: 言語選択 UI

**ユーザーストーリー:** ユーザーとして、直感的な UI で言語設定を変更したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Language_Picker SHALL TranscriptionPreviewPanel 内の上部に配置される
2. WHEN `auto`（言語自動判定）が選択された場合、THE Language_Picker の隣に検出言語ラベルと再判別ボタン（緑色アイコン）を表示する
3. THE 再判別ボタン SHALL ストリーミング中のみ有効で、押下時にストリーミングを再接続する
4. THE `auto` の表示名 SHALL 「言語自動判定」とする

### 要件 4: リアルタイム文字起こしの有効/無効切り替え

**ユーザーストーリー:** ユーザーとして、メイン画面からリアルタイム文字起こしの有効/無効を切り替えたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE 入力グループ SHALL 音声ソース Picker の隣にリアルタイム文字起こしのトグルスイッチを配置する
2. WHEN トグルが有効化された場合、リアルタイム文字起こしセクションを展開し、音声文字起こし・要約セクションを閉じる
3. WHEN トグルが無効化された場合、リアルタイム文字起こしセクションを非表示にし、音声文字起こし・要約セクションを展開する
4. THE トグルの状態 SHALL 設定ファイルに保存され、次回起動時に復元される

### 要件 5: 基盤モデル選択のメイン画面配置

**ユーザーストーリー:** ユーザーとして、要約の基盤モデルをメイン画面から直接選択したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE 要約セクション SHALL 基盤モデル選択 Picker を上部に配置する
2. THE 基盤モデル Picker SHALL 要約中は無効化される
3. THE 選択された基盤モデル SHALL 設定ファイルに保存され、次回起動時に復元される
4. THE 設定画面 SHALL リアルタイム設定と要約設定を含まない（メイン画面に移動済み）

### 要件 6: リアルタイム翻訳の条件

**ユーザーストーリー:** ユーザーとして、文字起こし言語と翻訳先言語が異なる場合のみ翻訳を実行してほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 指定言語モードの場合、THE Realtime_Transcription_ViewModel SHALL `selectedLanguage` のプレフィックスと翻訳先言語を比較し、異なる場合のみリアルタイム翻訳を実行する
2. WHEN 言語自動判定モードの場合、THE Realtime_Transcription_ViewModel SHALL 検出された言語のプレフィックスと翻訳先言語を比較し、異なる場合のみリアルタイム翻訳を実行する
