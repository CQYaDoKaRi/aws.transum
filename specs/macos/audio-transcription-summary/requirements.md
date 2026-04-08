# 要件定義ドキュメント（Requirements Document）

## はじめに（Introduction）

本ドキュメントは、macOS 向け音声文字起こし・要約アプリケーションの要件を定義する。ユーザーが Mac で録音した音声ファイル（m4a, wav など）や動画ファイル（mp4, mov など）をアプリケーションに入力し、音声認識（Speech-to-Text）による文字起こしと、文字起こし結果の自動要約（Summarization）を行う機能を提供する。また、PC のシステム音声キャプチャや画面録画からの文字起こしにも対応する。

## 用語集（Glossary）

- **App**: macOS 上で動作する音声文字起こし・要約アプリケーション本体
- **Transcriber**: 音声ファイルを受け取り、テキストに変換する音声認識コンポーネント
- **Summarizer**: 文字起こしテキストを受け取り、要約を生成するコンポーネント
- **AudioFile**: ユーザーが入力する音声ファイル（m4a, wav, mp3 などの形式）
- **VideoFile**: ユーザーが入力する動画ファイル（mp4, mov, m4v などの形式）
- **Transcript**: 音声ファイルから生成された文字起こしテキスト
- **Summary**: Transcript から生成された要約テキスト
- **FileImporter**: 音声・動画ファイルの読み込みとバリデーションを行うコンポーネント
- **AudioExtractor**: 動画ファイルから音声トラックを抽出するコンポーネント
- **SystemAudioCapture**: PC のシステム音声（内部オーディオ）やマイク音声をキャプチャするコンポーネント
- **ScreenRecorder**: 画面録画（映像+音声）を行うコンポーネント
- **ExportManager**: Transcript や Summary をファイルとして書き出すコンポーネント
- **AudioSourceType**: 録音時に選択可能な音源の種別（システム音声・マイク・特定アプリケーション）
- **AudioSourceProvider**: 利用可能な音源リソースの一覧を取得するコンポーネント

## 要件（Requirements）

### 要件 1: 音声・動画ファイルの読み込み（Media File Import）

**ユーザーストーリー:** ユーザーとして、Mac で録音した音声ファイルや動画ファイルをアプリケーションに読み込ませたい。それにより、文字起こし処理を開始できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL メディアファイルを選択するためのファイル選択ダイアログを提供する
2. WHEN ユーザーがメディアファイルをドラッグ＆ドロップした場合、THE FileImporter SHALL 該当ファイルを読み込む
3. THE FileImporter SHALL m4a, wav, mp3, aiff 形式の音声ファイルおよび mp4, mov, m4v 形式の動画ファイルを受け付ける
4. WHEN サポート対象外の形式のファイルが選択された場合、THE FileImporter SHALL 対応形式の一覧を含むエラーメッセージを表示する
5. WHEN メディアファイルが正常に読み込まれた場合、THE App SHALL ファイル名、ファイル形式、再生時間をユーザーに表示する
6. IF メディアファイルが破損している場合、THEN THE FileImporter SHALL 「ファイルが読み込めません」というエラーメッセージを表示する
7. WHEN 動画ファイルが読み込まれた場合、THE AudioExtractor SHALL 動画から音声トラックを自動的に抽出する
8. IF 動画ファイルに音声トラックが含まれていない場合、THEN THE AudioExtractor SHALL 「動画に音声トラックが含まれていません」というエラーメッセージを表示する

### 要件 2: 音声の文字起こし（Audio Transcription）

**ユーザーストーリー:** ユーザーとして、読み込んだ音声ファイルの内容を自動的にテキストに変換したい。それにより、音声の内容をテキストとして確認・活用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが文字起こしボタンを押した場合、THE Transcriber SHALL 読み込まれた AudioFile の文字起こしを開始する
2. WHILE 文字起こし処理が実行中の間、THE App SHALL 進捗状況をプログレスバーで表示する
3. WHEN 文字起こしが完了した場合、THE App SHALL 生成された Transcript をテキストエリアに表示する
4. THE Transcriber SHALL 日本語の音声を文字起こしする機能を提供する
5. THE Transcriber SHALL 英語の音声を文字起こしする機能を提供する
6. IF 文字起こし処理中にエラーが発生した場合、THEN THE App SHALL エラーの内容を含むメッセージを表示し、再試行ボタンを提供する
7. IF AudioFile の音声が無音のみの場合、THEN THE Transcriber SHALL 「音声が検出されませんでした」というメッセージを返す

### 要件 3: 文字起こし結果の要約（Transcript Summarization）

**ユーザーストーリー:** ユーザーとして、文字起こしされたテキストの要約を自動生成したい。それにより、長い音声の内容を短時間で把握できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN Transcript が生成された後にユーザーが要約ボタンを押した場合、THE Summarizer SHALL Transcript の要約を生成する
2. WHEN 要約が完了した場合、THE App SHALL 生成された Summary を Transcript とは別のセクションに表示する
3. WHILE 要約処理が実行中の間、THE App SHALL 処理中であることを示すインジケーターを表示する
4. THE Summarizer SHALL 元の Transcript の主要なポイントを含む Summary を生成する
5. IF Transcript が空または極端に短い（50文字未満）場合、THEN THE Summarizer SHALL 「要約するには内容が不十分です」というメッセージを返す
6. IF 要約処理中にエラーが発生した場合、THEN THE App SHALL エラーの内容を含むメッセージを表示し、再試行ボタンを提供する

### 要件 4: 結果のエクスポート（Result Export）

**ユーザーストーリー:** ユーザーとして、文字起こし結果と要約をファイルとして保存したい。それにより、後から参照したり他のアプリケーションで活用できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーがエクスポートボタンを押した場合、THE ExportManager SHALL Transcript と Summary をテキストファイル（.txt）として保存する
2. THE ExportManager SHALL 保存先フォルダを選択するためのダイアログを提供する
3. WHEN エクスポートが完了した場合、THE App SHALL 保存完了のメッセージを表示する
4. IF 保存先に書き込み権限がない場合、THEN THE ExportManager SHALL 「保存先に書き込みできません。別のフォルダを選択してください」というエラーメッセージを表示する
5. THE ExportManager SHALL 文字起こし結果を `元ファイル名.transcript.txt` として保存する
6. THE ExportManager SHALL 要約結果を `元ファイル名.summary.txt` として保存する
7. THE ExportManager SHALL エラーログを `日付_時刻.error.log` として、エラー発生時のみ出力する

### 要件 5: 音声の再生（Audio Playback）

**ユーザーストーリー:** ユーザーとして、読み込んだ音声ファイルをアプリケーション内で再生したい。それにより、文字起こし結果と音声を照らし合わせて確認できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 音声ファイルが読み込まれた状態でユーザーが再生ボタンを押した場合、THE App SHALL AudioFile の再生を開始する
2. WHILE AudioFile が再生中の間、THE App SHALL 現在の再生位置をシークバーで表示する
3. WHEN ユーザーが一時停止ボタンを押した場合、THE App SHALL 再生を一時停止する
4. WHEN ユーザーがシークバーを操作した場合、THE App SHALL 指定された位置から再生を再開する

### 要件 6: アプリケーションの基本構成（Application Foundation）

**ユーザーストーリー:** ユーザーとして、macOS のネイティブアプリケーションとして快適に操作したい。それにより、Mac の操作体験と一貫した使い心地を得られるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL macOS ネイティブアプリケーションとして動作する
2. THE App SHALL macOS 14（Sonoma）以降をサポートする
3. THE App SHALL macOS のダークモードとライトモードの両方に対応する
4. WHEN App が起動した場合、THE App SHALL メインウィンドウを表示し、音声ファイルの読み込みを促すガイダンスを表示する
5. THE App SHALL macOS 標準のキーボードショートカット（Command+O でファイルを開く、Command+S で保存）に対応する

### 要件 7: システム音声キャプチャ（System Audio Capture）

**ユーザーストーリー:** ユーザーとして、PC で再生中の音声（会議、動画、音楽など）をキャプチャして文字起こししたい。それにより、ファイルとして保存されていない音声も文字起こしできるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 「システム音声を録音」ボタンを提供する
2. WHEN ユーザーがシステム音声録音を開始した場合、THE SystemAudioCapture SHALL ScreenCaptureKit を使用してシステム音声のキャプチャを開始する
3. WHILE システム音声キャプチャ中の間、THE App SHALL 録音中であることを示すインジケーターと経過時間を表示する
4. WHILE システム音声キャプチャ中の間、THE App SHALL 音声レベルメーターを表示する
5. WHEN ユーザーが停止ボタンを押した場合、THE SystemAudioCapture SHALL キャプチャを停止し、録音された音声を M4A 形式（AAC）の AudioFile として読み込む
6. THE App SHALL キャプチャのキャンセルボタンを提供する
7. IF 画面収録の権限が付与されていない場合、THEN THE App SHALL 権限設定への案内を表示する

### 要件 8: 画面録画（Screen Recording）

**ユーザーストーリー:** ユーザーとして、画面を録画しながら音声も同時にキャプチャして文字起こししたい。それにより、画面の内容と音声を合わせて記録・文字起こしできるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 「画面を録画」ボタンを提供する
2. WHEN ユーザーが画面録画を開始した場合、THE ScreenRecorder SHALL ScreenCaptureKit を使用して画面と音声の同時キャプチャを開始する
3. WHILE 画面録画中の間、THE App SHALL 録画中であることを示すインジケーターと経過時間を表示する
4. WHEN ユーザーが停止ボタンを押した場合、THE ScreenRecorder SHALL 録画を停止し、THE AudioExtractor SHALL 録画された動画から音声を自動抽出する
5. WHILE 音声抽出中の間、THE App SHALL 「動画から音声を抽出中...」というインジケーターを表示する
6. THE App SHALL 録画のキャンセルボタンを提供する

### 要件 9: CPU・メモリ使用状況の表示（System Resource Monitoring）

**ユーザーストーリー:** ユーザーとして、アプリケーション使用中にシステムの CPU・メモリ使用状況を確認したい。それにより、リソース消費を把握しながら作業できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL メインウィンドウ下部にステータスバーを表示する
2. THE StatusBarView SHALL CPU 使用率をリアルタイムで表示する
3. THE StatusBarView SHALL メモリ使用量をリアルタイムで表示する
4. THE StatusBarView SHALL 定期的にシステムリソース情報を更新する

### 要件 10: 音源リソースの選択（Audio Source Selection）

**ユーザーストーリー:** ユーザーとして、録音時にシステム音声・マイク・特定アプリケーションの音声から音源を選択したい。それにより、目的に応じた音声を録音できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 録音開始前に音源リソースを選択するドロップダウン（Picker）を提供する
2. THE App SHALL 以下の音源種別を選択肢として提供する:
   - システム全体の音声（ScreenCaptureKit 使用）
   - マイク入力（AVCaptureSession 使用、内蔵マイク・外部マイクを含む）
   - 特定アプリケーションの音声（ScreenCaptureKit の SCContentFilter 使用）
3. THE App SHALL 画面表示時に利用可能な音源リソース一覧を自動取得する
4. WHEN マイクが選択された場合、THE SystemAudioCapture SHALL AVCaptureSession を使用してマイク音声をキャプチャする
5. WHEN システム音声またはアプリケーションが選択された場合、THE SystemAudioCapture SHALL ScreenCaptureKit を使用して音声をキャプチャする
6. THE App SHALL マイクデバイスの一覧を AVCaptureDevice.DiscoverySession から取得する
7. WHEN ユーザーが録音停止ボタンを押した場合、THE App SHALL 録音ファイルを保存先に保存し、音声プレーヤーに読み込む（文字起こしは自動実行しない）
8. THE App SHALL 録音停止後、ユーザーが右パネルの「文字起こし＋要約」ボタンで明示的に文字起こしを開始できるようにする

### 要件 11: 折りたたみセクションの自動開閉連動（Collapsible Section Auto-Toggle）

**ユーザーストーリー:** ユーザーとして、操作に応じて関連するセクションが自動的に展開・折りたたみされてほしい。それにより、現在の作業に集中できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 録音/録画が開始された場合、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを展開し、音声文字起こしセクションと要約セクションを折りたたむ
2. WHEN 録音/録画が停止された場合、THE App SHALL 音声文字起こしセクションと要約セクションを展開する
3. WHEN ファイルドロップゾーンでファイルが選択された場合（D&D またはファイル選択ダイアログ）、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを折りたたむ
4. WHEN 「ファイルから要約」でファイルが選択された場合、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを折りたたむ
5. WHEN 文字起こし結果（Transcript）がクリアまたは更新された場合、THE App SHALL 音声文字起こしの翻訳パネルをリセットする
6. WHEN 要約結果（Summary）がクリアまたは更新された場合、THE App SHALL 要約の翻訳パネルをリセットする
7. THE App SHALL 文字起こし結果エリアおよび要約結果エリアに操作案内テキストを表示しない

### 要件 14: 録音中の UI 制御（Recording UI Control）

**ユーザーストーリー:** ユーザーとして、録音中に誤操作で設定変更やファイル読み込みをしたくない。それにより、録音に集中できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE 録音/録画中の間、THE App SHALL 設定画面を開くボタンを無効にする
2. WHILE 録音/録画中の間、THE App SHALL 音声文字起こしセクションのファイルドラッグ＆ドロップを無効にする
3. WHILE 録音/録画中の間、THE App SHALL 音声文字起こしセクションの「ファイルを選択」ボタンを無効にする
4. WHILE 録音/録画中の間、THE App SHALL 要約セクションの「ファイルから要約」ボタンを無効にする
5. WHILE 録音/録画中の間、THE StatusBarView SHALL 録音経過時間を「録音中 MM:SS」形式で表示する
6. WHILE 録音/録画中の間、THE App SHALL 入力ソースの選択コントロールを無効にする
7. WHILE 録音/録画中の間、THE App SHALL ファイル分割時間の選択コントロールを無効にする

### 要件 15: リアルタイム文字起こしの有効/無効切り替え（Realtime Transcription Toggle）

**ユーザーストーリー:** ユーザーとして、録音中でもリアルタイム文字起こしの有効/無効を切り替えたい。それにより、必要に応じてリソース消費を抑えたり、文字起こしを再開できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN リアルタイム文字起こしが無効にされた場合、THE App SHALL リアルタイム文字起こしのストリーミングを停止する
2. WHEN リアルタイム文字起こしが無効にされた場合、THE App SHALL リアルタイム文字起こしのテキストエリアとリアルタイム翻訳のテキストエリアをクリアする
3. WHEN リアルタイム文字起こしが有効にされた場合かつ録音中の場合、THE App SHALL リアルタイム文字起こしとリアルタイム翻訳を開始する
4. WHEN リアルタイム文字起こしが有効にされた場合、THE App SHALL 既存のストリーム出力ファイルがあれば追記する

### 要件 16: 設定の永続化（Settings Persistence）

**ユーザーストーリー:** ユーザーとして、ファイル分割時間やリアルタイム文字起こしの ON/OFF 設定が次回起動時に復元されてほしい。それにより、毎回設定し直す手間を省きたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL ファイル分割間隔（splitIntervalMinutes）を設定ファイル（settings.json）に保存する
2. THE App SHALL リアルタイム文字起こしの有効/無効（isRealtimeEnabled）を設定ファイルに保存する
3. WHEN App が起動した場合、THE App SHALL 設定ファイルから分割間隔とリアルタイム設定を復元する
4. THE App SHALL 設定変更時に即座に設定ファイルに保存する
5. THE App SHALL 設定画面の全設定項目（認証情報・リージョン・S3・ディレクトリ・モデル）を変更時に即座に保存し、アプリに反映する

### 要件 17: 二重起動防止（Single Instance）

**ユーザーストーリー:** ユーザーとして、アプリケーションが二重起動しないようにしたい。それにより、リソースの無駄遣いや設定の競合を防ぎたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 同じアプリケーションが既に起動中の場合、THE App SHALL 新しいインスタンスを起動せずに終了する
2. THE App SHALL macOS では NSRunningApplication、Windows では Mutex を使用して二重起動を検出する

### 要件 12: アプリアイコン（Application Icon）

**ユーザーストーリー:** ユーザーとして、Dock やアプリケーション一覧でアプリを視覚的に識別したい。それにより、他のアプリケーションと区別しやすくしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 起動時にアプリアイコンを Dock に表示する
2. THE App SHALL 青いグラデーション背景に白い波形バー（音声）、ドキュメントアイコン（文字起こし・要約）、「T」文字（Transcription）を組み合わせたデザインのアイコンを使用する
3. THE App SHALL プログラムで NSImage を生成し NSApplication.applicationIconImage に設定する

### 要件 13: インストーラー（Installer）

**ユーザーストーリー:** ユーザーとして、DMGファイルからアプリケーションを簡単にインストールしたい。それにより、Applicationsフォルダにドラッグ＆ドロップするだけで利用開始できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL .app バンドル形式でパッケージングされる
2. THE App SHALL DMG インストーラーとして配布される
3. THE DMG SHALL .app と Applications フォルダへのシンボリックリンクを含む
4. THE App SHALL Info.plist にマイク、音声認識、画面収録の使用説明を含む
5. THE App SHALL ビルドスクリプト（build-app.sh）で再現可能にパッケージを作成できる
