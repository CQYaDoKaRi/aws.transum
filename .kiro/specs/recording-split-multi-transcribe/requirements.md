# 要件定義（Requirements）

## はじめに

録音機能の改善と音声文字起こしの複数ファイル対応を行う。録音ファイルを1分ごとに分割して保存し、分割された複数ファイルを音声文字起こしのファイルリストに自動追加する。音声文字起こしでは複数ファイルを選択・一括文字起こしし、結果をファイル順に結合して表示・保存する。また、録音開始/停止操作中のボタン無効化とステータスバーメッセージ表示、および入力グループの不要なラベル削除を行う。macOS（SwiftUI）と Windows（WinUI 3）の両プラットフォームで同一仕様とする。

## 用語集（Glossary）

- **Recording_Service**: 音声録音を担当するサービス（macOS: `SystemAudioCapture` / Windows: `AudioCaptureService`）
- **Split_Recording_Manager**: 録音ファイルの1分ごとの分割を管理するコンポーネント
- **Transcribe_Client**: Amazon Transcribe を使用した文字起こしクライアント（macOS: `TranscribeClient` / Windows: `TranscribeClient`）
- **App_ViewModel**: アプリケーション全体の状態管理を担当する ViewModel（macOS: `AppViewModel` / Windows: `MainViewModel`）
- **Status_Bar**: アプリケーション下部のステータスバー（macOS: `StatusBarView` / Windows: `MainPage` 下部の Grid）
- **File_List**: 音声文字起こしセクションにおける選択ファイルリスト
- **Transcript_View**: 音声文字起こしの結果表示領域（macOS: `TranscriptView` / Windows: `TranscriptText`）
- **Input_Section**: メイン画面上部の入力グループ（録音コントロール等を含むセクション）

## 要件（Requirements）

### 要件 1: 入力グループのラベル削除

**ユーザーストーリー:** ユーザーとして、入力グループの不要な「録音中」「録画中」表示ラベルを削除し、画面をすっきりさせたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Input_Section SHALL 録音中・録画中の状態を示すテキストラベル（「録音中」「録画中」）を表示しない
2. THE Input_Section SHALL 録音中・録画中の状態表示として赤い丸インジケーターとテキストラベルの両方を削除する
3. THE Status_Bar SHALL 録音中の状態表示を引き続き提供する（ステータスバーの録音時間表示は維持する）

### 要件 2: 録音開始時のボタン無効化とステータスバーメッセージ

**ユーザーストーリー:** ユーザーとして、録音ボタンを押してから録音が実際に開始されるまでの間、二重操作を防止し、現在の状態を把握したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 録音ボタンが押された場合、THE App_ViewModel SHALL 録音ボタンを即座に無効化する
2. WHEN 録音ボタンが押された場合、THE Status_Bar SHALL 「録音開始中」というメッセージを表示する
3. WHEN Recording_Service が録音を正常に開始した場合、THE App_ViewModel SHALL 録音停止ボタンを有効化する
4. WHEN Recording_Service が録音を正常に開始した場合、THE Status_Bar SHALL 「録音開始中」メッセージを通常の録音中表示に切り替える
5. IF Recording_Service の録音開始中にエラーが発生した場合、THEN THE App_ViewModel SHALL 録音ボタンを再度有効化し、エラーメッセージを表示する

### 要件 3: 録音停止時のボタン無効化とステータスバーメッセージ

**ユーザーストーリー:** ユーザーとして、録音停止ボタンを押してから録音が実際に停止されるまでの間、二重操作を防止し、現在の状態を把握したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 録音停止ボタンが押された場合、THE App_ViewModel SHALL 録音停止ボタンを即座に無効化する
2. WHEN 録音停止ボタンが押された場合、THE Status_Bar SHALL 「録音停止中」というメッセージを表示する
3. WHEN Recording_Service が録音を正常に停止した場合、THE App_ViewModel SHALL 録音ボタンを有効化する
4. WHEN Recording_Service が録音を正常に停止した場合、THE Status_Bar SHALL 「録音停止中」メッセージをクリアする
5. IF Recording_Service の録音停止中にエラーが発生した場合、THEN THE App_ViewModel SHALL 録音停止ボタンを再度有効化し、エラーメッセージを表示する


### 要件 4: 録音ファイルの1分分割

**ユーザーストーリー:** ユーザーとして、長時間の録音を1分ごとに分割されたファイルとして保存し、管理しやすくしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE Recording_Service が録音中の場合、THE Split_Recording_Manager SHALL 1分（60秒）ごとに現在の録音ファイルを確定し、新しい録音ファイルを開始する
2. THE Split_Recording_Manager SHALL 分割ファイルのファイル名末尾に「-」と3桁の連番を付与する（例: `20250101_120000-001.m4a`, `20250101_120000-002.m4a`）
3. THE Split_Recording_Manager SHALL 連番を001から開始し、分割数に応じて002, 003, ... と増加させる
4. THE Split_Recording_Manager SHALL 連番を3桁のゼロ埋めで表示する（1つ目は001、10個目は010、100個目は100）
5. WHEN 録音が停止された場合、THE Split_Recording_Manager SHALL 最後の分割ファイルを確定して保存する（1分未満の端数も保存する）
6. THE Split_Recording_Manager SHALL 各分割ファイルを有効な音声ファイルとして保存する（各ファイルが単独で再生可能であること）
7. THE Split_Recording_Manager SHALL macOS では M4A（AAC）形式、Windows では WAV 形式で分割ファイルを保存する

### 要件 5: 分割ファイルのファイルリスト自動追加

**ユーザーストーリー:** ユーザーとして、録音完了後に分割されたファイルが自動的に音声文字起こしのファイルリストに追加されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Recording_Service が録音を停止した場合、THE App_ViewModel SHALL 録音で生成された全分割ファイルを File_List に連番順で追加する
2. THE File_List SHALL 各ファイルのファイル名、再生時間、ファイルサイズを表示する
3. THE File_List SHALL 追加されたファイルを全て選択状態で初期表示する
4. WHEN ユーザーがファイルを手動で追加した場合、THE File_List SHALL 追加されたファイルを既存リストの末尾に追加する

### 要件 6: 音声文字起こしの複数ファイル選択

**ユーザーストーリー:** ユーザーとして、音声文字起こしで複数のファイルを選択して一括処理したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE File_List SHALL 複数ファイルの選択を許可する（チェックボックスまたは複数選択 UI）
2. THE File_List SHALL 全選択/全解除の操作を提供する
3. WHEN ファイル選択ダイアログからファイルを追加する場合、THE File_List SHALL 複数ファイルの同時選択を許可する
4. WHEN ドラッグ＆ドロップでファイルを追加する場合、THE File_List SHALL 複数ファイルの同時追加を許可する
5. THE File_List SHALL 選択されたファイルの順序をドラッグ操作またはリスト表示順で管理する

### 要件 7: 複数ファイルの一括文字起こしと結果結合

**ユーザーストーリー:** ユーザーとして、選択した複数ファイルの文字起こし結果をファイル順に結合して確認・保存したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 文字起こしが実行された場合、THE Transcribe_Client SHALL File_List で選択された全ファイルを選択順に文字起こしする
2. THE Transcribe_Client SHALL 各ファイルの文字起こし進捗を個別に追跡し、全体の進捗として表示する
3. WHEN 全ファイルの文字起こしが完了した場合、THE App_ViewModel SHALL 選択されたファイル順に文字起こし結果を結合する
4. THE App_ViewModel SHALL 結合された文字起こし結果を Transcript_View にセットする
5. THE App_ViewModel SHALL 結合された文字起こし結果を音声文字起こしファイル（`.transcript.txt`）として保存する
6. IF いずれかのファイルの文字起こし中にエラーが発生した場合、THEN THE App_ViewModel SHALL エラーが発生したファイル名とエラー内容を表示し、残りのファイルの文字起こしを継続する

### 要件 8: クロスプラットフォーム仕様統一

**ユーザーストーリー:** ユーザーとして、macOS と Windows で同じ操作体験を得たい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App_ViewModel SHALL macOS（SwiftUI）と Windows（WinUI 3）で同一の録音分割ロジックを実装する
2. THE App_ViewModel SHALL macOS と Windows で同一のファイル命名規則（タイムスタンプ + 3桁連番）を使用する
3. THE App_ViewModel SHALL macOS と Windows で同一の複数ファイル選択 UI パターンを提供する
4. THE App_ViewModel SHALL macOS と Windows で同一の文字起こし結果結合ロジックを実装する
5. THE Status_Bar SHALL macOS と Windows で同一のステータスメッセージ（「録音開始中」「録音停止中」）を表示する
