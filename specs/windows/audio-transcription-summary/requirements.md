# 要件定義ドキュメント（Requirements Document）- Windows版

## はじめに（Introduction）

本ドキュメントは、Windows向け音声文字起こし・要約アプリケーション（WinUI 3 / .NET 8）の要件を定義する。macOS版と同等の機能を提供し、ユーザーが音声ファイル（m4a, wav等）や動画ファイル（mp4, mov等）を入力し、音声認識による文字起こしと自動要約を行う。PCのシステム音声キャプチャやマイク入力からの文字起こしにも対応する。

## 用語集（Glossary）

- **App**: Windows版AudioTranscriptionSummaryアプリケーション（WinUI 3 / .NET 8）
- **Transcriber**: Amazon Transcribeを使用して音声をテキストに変換するコンポーネント
- **Summarizer**: 抽出型要約を実行するコンポーネント
- **AudioFile**: ユーザーが入力する音声ファイル（m4a, wav, mp3等）
- **VideoFile**: ユーザーが入力する動画ファイル（mp4, mov, m4v等）
- **Transcript**: 音声から生成された文字起こしテキスト
- **Summary**: Transcriptから生成された要約テキスト
- **FileImporter**: 音声・動画ファイルの読み込みとバリデーションを行うコンポーネント
- **AudioCaptureService**: NAudioを使用してシステム音声（WasapiLoopbackCapture）およびマイク入力（WaveInEvent）をキャプチャするコンポーネント
- **ExportManager**: TranscriptやSummaryをファイルとして書き出すコンポーネント
- **AudioSourceType**: 録音時に選択可能な音源の種別（システム音声・マイク）
- **SettingsStore**: アプリ設定をJSONファイルに永続化するコンポーネント（%APPDATA%\AudioTranscriptionSummary\settings.json）

## 要件（Requirements）

### 要件 1: 音声・動画ファイルの読み込み（Media File Import）

**ユーザーストーリー:** ユーザーとして、音声ファイルや動画ファイルをアプリケーションに読み込ませたい。それにより、文字起こし処理を開始できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL FileOpenPickerを使用してメディアファイル選択ダイアログを提供する（ファイル選択ボタンにFontIcon &#xE8E5; アイコンを使用）
2. WHEN ユーザーがメディアファイルをドラッグ＆ドロップした場合、THE FileImporter SHALL AllowDrop/DragOver/Dropイベントで該当ファイルを読み込む（ドロップゾーンにFontIcon &#xE898; アップロード矢印アイコンを表示）
3. THE FileImporter SHALL m4a, wav, mp3, aiff形式の音声ファイルおよびmp4, mov, m4v形式の動画ファイルを受け付ける
4. WHEN サポート対象外の形式のファイルが選択された場合、THE FileImporter SHALL 対応形式の一覧を含むエラーメッセージを表示する
5. WHEN メディアファイルが正常に読み込まれた場合、THE App SHALL ファイル名、ファイル形式、再生時間を表示する
6. IF メディアファイルが破損している場合、THEN THE FileImporter SHALL 「ファイルが読み込めません」というエラーメッセージを表示する
7. WHEN ファイルが読み込まれた場合、THE App SHALL 以前のTranscriptとSummaryをクリアし、AudioPlayerに読み込む

### 要件 2: 音声の文字起こし（Audio Transcription）

**ユーザーストーリー:** ユーザーとして、読み込んだ音声ファイルの内容を自動的にテキストに変換したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN ユーザーが「文字起こし＋要約」ボタンを押した場合、THE Transcriber SHALL Amazon Transcribe APIを使用して文字起こしを開始する
2. WHILE 文字起こし処理が実行中の間、THE App SHALL ProgressBarで進捗状況を表示する
3. WHEN 文字起こしが完了した場合、THE App SHALL 生成されたTranscriptをテキストエリアに表示する
4. THE Transcriber SHALL 日本語・英語の音声を文字起こしする機能を提供する
5. IF 文字起こし処理中にエラーが発生した場合、THEN THE App SHALL ContentDialogでエラーメッセージと再試行ボタンを表示する
6. IF AudioFileの音声が無音のみの場合、THEN THE Transcriber SHALL 「音声が検出されませんでした」というメッセージを返す
7. WHEN 文字起こしが完了した場合、THE App SHALL 自動的に要約処理を開始する

### 要件 3: 文字起こし結果の要約（Transcript Summarization）

**ユーザーストーリー:** ユーザーとして、文字起こしされたテキストの要約を自動生成したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE Summarizer SHALL 抽出型要約（文分割・単語頻度・位置・長さスコアリング）を実装する
2. THE Summarizer SHALL 約30%の文（最低1文）をスコア順に選択し、元の文順序を保持する
3. WHEN 要約が完了した場合、THE App SHALL SummaryをTranscriptとは別のExpanderセクションに表示する
4. IF Transcriptが50文字未満の場合、THEN THE Summarizer SHALL 「要約するには内容が不十分です」というメッセージを返す
5. THE Summarizer SHALL 位置スコア: 先頭文1.0、末尾文0.5、中間文は漸減

### 要件 4: 結果のエクスポート（Result Export）

**ユーザーストーリー:** ユーザーとして、文字起こし結果と要約をファイルとして保存したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN エクスポート保存先が設定済みの場合、THE ExportManager SHALL 文字起こし＋要約完了後に自動的にTranscriptとSummaryをテキストファイルとして保存する
2. THE ExportManager SHALL エクスポート保存先が設定済みの場合はダイアログなしで直接保存する（CommandBarにエクスポートボタンは配置しない）
3. THE ExportManager SHALL 文字起こし結果を `{音声ファイル名}.transcript.txt`、要約を `{音声ファイル名}.summary.txt` として保存する（音声ファイル名ベース、拡張子除去）
4. THE ExportManager SHALL UTF-8エンコーディングを使用する
5. IF 保存先に書き込み権限がない場合、THEN THE ExportManager SHALL エラーメッセージを表示する
6. WHEN 文字起こし＋要約が成功しエクスポート保存先が設定済みの場合、THE App SHALL 自動エクスポートする

### 要件 5: 音声の再生（Audio Playback）

**ユーザーストーリー:** ユーザーとして、読み込んだ音声ファイルをアプリケーション内で再生したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL NAudio（WaveOutEvent + AudioFileReader）を使用して音声を再生する
2. WHILE 再生中の間、THE App SHALL Sliderで再生位置を表示し、100msごとにDispatcherTimerで更新する。AudioPlayerはGrid レイアウトを使用し、Sliderがウィンドウ幅に伸縮する
3. WHEN ユーザーがSliderを操作した場合、THE App SHALL 指定位置にシークする
4. THE App SHALL 再生時間を "mm:ss / mm:ss" 形式で表示する
5. WHEN 再生が終端に達した場合、THE App SHALL 停止して先頭にリセットする

### 要件 6: アプリケーションの基本構成（Application Foundation）

**ユーザーストーリー:** ユーザーとして、Windowsネイティブアプリケーションとして快適に操作したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL WinUI 3（Windows App SDK）ネイティブアプリケーションとして動作する
2. THE App SHALL Windows 10 19041以降をサポートする
3. THE App SHALL Windowsのダークモードとライトモードの両方に対応する（WinUI 3テーマ自動対応）
4. WHEN Appが起動した場合、THE App SHALL メインウィンドウ（1200x800）を表示する
5. THE App SHALL 「文字起こし＋要約」ボタン1つで文字起こし→要約→自動エクスポートを一括実行する（CommandBarにエクスポートボタンは配置しない）

### 要件 7: システム音声キャプチャ（System Audio Capture）

**ユーザーストーリー:** ユーザーとして、PCで再生中の音声をキャプチャして文字起こししたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 「録音」ボタンを提供する
2. WHEN ユーザーがシステム音声録音を開始した場合、THE AudioCaptureService SHALL NAudio WasapiLoopbackCaptureを使用してシステム音声のキャプチャを開始する
3. WHEN ユーザーがマイクを選択して録音を開始した場合、THE AudioCaptureService SHALL NAudio WaveInEventを使用してマイク音声をキャプチャする
4. WHILE キャプチャ中の間、THE App SHALL 録音中インジケーター（赤）と音声レベルメーター（ProgressBar）を表示する
5. WHEN ユーザーが停止ボタンを押した場合、THE AudioCaptureService SHALL キャプチャを停止し、WAVファイルとして設定の録音保存先ディレクトリ（RecordingDirectoryPath）に保存する
6. THE App SHALL キャプチャのキャンセルボタンを提供する
7. WHEN 録音停止後、THE App SHALL 録音ファイルをAudioPlayerに読み込む（文字起こしは自動実行しない）
8. THE AudioCaptureService SHALL SettingsStoreからRecordingDirectoryPathを読み取り、録音ファイルの保存先として使用する

### 要件 8: ファイル命名規則（File Naming Convention）

**ユーザーストーリー:** ユーザーとして、生成されるファイルの名前が日時ベースで統一されていてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL すべての生成ファイルの名前に日時（`yyyyMMdd_HHmmss` 形式）を使用する
2. THE AudioCaptureService SHALL 録音ファイルを `yyyyMMdd_HHmmss.wav` として保存する（プレフィックスなし）
3. THE ExportManager SHALL 文字起こし結果を `{音声ファイル名}.transcript.txt` として保存する（音声ファイル名ベース）
4. THE ExportManager SHALL 要約結果を `{音声ファイル名}.summary.txt` として保存する（音声ファイル名ベース）
5. THE App SHALL ファイルから要約の場合、`{読み込みファイル名}.summary.txt` として保存する

### 要件 9: CPU・メモリ使用状況の表示（System Resource Monitoring）

**ユーザーストーリー:** ユーザーとして、アプリケーション使用中にCPU・メモリ使用状況を確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL メインウィンドウ下部に全幅のステータスバーをGrid で表示する（背景色 #E0E0E0、テキスト色 #808080、右寄せ）
2. THE StatusBar SHALL CPU使用率（アプリ・全体）をリアルタイムで表示する
3. THE StatusBar SHALL メモリ使用量（アプリMB・全体GB・%）をリアルタイムで表示する
4. THE StatusBar SHALL 2秒ごとにDispatcherTimerで更新する
5. THE StatusBar SHALL System.Diagnostics.ProcessとGCを使用してメトリクスを取得する

### 要件 10: 音源リソースの選択（Audio Source Selection）

**ユーザーストーリー:** ユーザーとして、録音時にシステム音声・マイクから音源を選択したい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 録音開始前に音源リソースを選択するComboBoxを提供する（ラベルなし）
2. THE App SHALL 以下の音源種別を選択肢として提供する:
   - システム音声（NAudio WasapiLoopbackCapture）
   - マイク入力（NAudio WaveInEvent、内蔵・外部マイクを含む）
3. THE App SHALL 画面表示時にNAudioで利用可能な音源デバイス一覧を自動取得し、デフォルトでシステム音声（ループバック）を選択する
4. WHEN ユーザーが録音停止ボタンを押した場合、THE App SHALL 録音ファイルを保存先に保存し、AudioPlayerに読み込む

### 要件 11: 折りたたみセクションの自動開閉連動（Collapsible Section Auto-Toggle）

**ユーザーストーリー:** ユーザーとして、操作に応じて関連するセクションが自動的に展開・折りたたみされてほしい。それにより、現在の作業に集中できるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 録音が開始された場合、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを展開し、音声文字起こしセクションと要約セクションを折りたたむ
2. WHEN 録音が停止された場合、THE App SHALL 音声文字起こしセクションと要約セクションを展開する
3. WHEN ファイルドロップゾーンでファイルが選択された場合（D&D またはファイル選択ダイアログ）、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを折りたたむ
4. WHEN 「ファイルから要約」でファイルが選択された場合、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを折りたたむ

### 要件 12: UIスタイリング（UI Styling）

**ユーザーストーリー:** ユーザーとして、各セクションが色分けされ、アイコン付きで視覚的にわかりやすいUIを使いたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 各Expanderヘッダーに色付き背景のBorderとFontIconアイコンを表示する:
   - 入力: 青 (#200078D4) + FontIcon &#xE720;
   - リアルタイム文字起こし: 赤 (#20E74856) + FontIcon &#xE8D6;
   - 音声文字起こし: 緑 (#2016C60C) + FontIcon &#xE8C1;
   - 要約: オレンジ (#20F7630C) + FontIcon &#xE8A5;
2. THE App SHALL すべてのテキストエリアにBorderフレーム（BorderThickness=1, CornerRadius=4）を適用する
3. THE App SHALL コピーボタンにFontIcon &#xE8C8; アイコンを使用する
4. THE App SHALL 翻訳ボタンにFontIcon &#xE8C3; アイコンを使用する

### 要件 13: 文字起こし言語選択（Transcription Language Selection）

**ユーザーストーリー:** ユーザーとして、文字起こしの言語を選択したい。それにより、精度の高い文字起こし結果を得られるようにしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL TranscriptionLanguage列挙型で21言語＋自動判別（Auto）を定義する（日本語、英語、中国語、韓国語、フランス語、ドイツ語、スペイン語、ポルトガル語、イタリア語、ヒンディー語、アラビア語、ロシア語、トルコ語、オランダ語、スウェーデン語、ポーランド語、タイ語、インドネシア語、ベトナム語、マレー語）
2. THE App SHALL 「文字起こし＋要約」ボタンの横にTranscriptionLangComboを配置し、言語を選択できるようにする
3. WHEN 「自動判別」が選択された場合、THE TranscribeClient SHALL `IdentifyLanguage=true` を使用して言語を自動判別する
4. THE App SHALL バッチ文字起こしとリアルタイム文字起こしの両方でTranscriptionLanguageを使用する

### 要件 14: テキストクリア動作（Text Clearing Behavior）

**ユーザーストーリー:** ユーザーとして、新しい操作を開始したときに前回の結果が自動的にクリアされてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 文字起こしが開始された場合、THE App SHALL Transcript、Summary、およびそれぞれの翻訳テキストをクリアする
2. WHEN Transcriptが設定またはクリアされた場合、THE App SHALL 文字起こし翻訳テキストをクリアする
3. WHEN 要約が開始された場合、THE App SHALL Summaryおよび要約翻訳テキストをクリアする
4. WHEN 録音が開始された場合、THE App SHALL すべてのテキスト（リアルタイム、文字起こし、要約、各翻訳）をクリアする

### 要件 15: ボタン状態管理（Button State Management）

**ユーザーストーリー:** ユーザーとして、操作できないボタンが無効化されていてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 「文字起こし＋要約」ボタンを、音声ファイル未選択時または文字起こし中に無効化する
2. THE App SHALL 「ファイルから要約」「要約」ボタンを、文字起こし中または要約中に無効化する
3. THE App SHALL コピーボタンを、対応するテキストが空の場合に無効化する
4. THE App SHALL 翻訳ボタンを、ソーステキストが空の場合に無効化する
5. THE App SHALL 要約中にProgressRingを表示する
6. WHILE 録音中の間、THE App SHALL 設定ボタン、ファイル選択ボタン、ドラッグ＆ドロップ、「ファイルから要約」ボタン、「要約」ボタン、入力ソース選択、ファイル分割時間選択を無効化する

### 要件 16: テキストエリアの高さ統一とリサイズ（Text Area Height and Resize）

**ユーザーストーリー:** ユーザーとして、テキストエリアの高さが統一され、ウィンドウサイズに応じて調整されてほしい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL すべてのテキストエリアの初期高さを150pxに統一する
2. THE App SHALL SizeChangedハンドラでウィンドウリサイズ時にテキストエリアの高さを動的に調整する
3. THE App SHALL テキストエリアの最小高さを150pxとする

### 要件 17: アプリアイコン（Application Icon）

**ユーザーストーリー:** ユーザーとして、タスクバーやウィンドウタイトルでアプリを視覚的に識別したい。それにより、他のアプリケーションと区別しやすくしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 起動時にアプリアイコンをウィンドウタイトルバーとタスクバーに表示する
2. THE App SHALL 青いグラデーション背景に白い波形バー（音声）、ドキュメントアイコン（文字起こし・要約）、「T」文字（Transcription）を組み合わせたデザインのアイコンを使用する
3. THE App SHALL System.Drawing.Common でICOファイルを生成し AppWindow.SetIcon で設定する
4. THE App SHALL 生成したICOファイルを %APPDATA%\AudioTranscriptionSummary\app.ico にキャッシュする

### 要件 18: 録音時間表示（Recording Duration Display）

**ユーザーストーリー:** ユーザーとして、録音中に経過時間を確認したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHILE 録音中の間、THE App SHALL ステータスバーに「音声をキャプチャ中... mm:ss」形式で録音経過時間を表示する
2. THE App SHALL 録音経過時間を2秒ごとに更新する
3. WHEN 録音が停止またはキャンセルされた場合、THE App SHALL ステータスバーの録音情報をクリアする

### 要件 19: リアルタイム文字起こしトグル（Realtime Transcription Toggle）

**ユーザーストーリー:** ユーザーとして、メイン画面からリアルタイム文字起こしの有効/無効を切り替えたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 入力セクションにToggleSwitchを配置し、リアルタイム文字起こしの有効/無効を切り替えられるようにする
2. THE ToggleSwitch SHALL OnContent/OffContentに「リアルタイム文字起こし」を表示する
3. WHEN トグルが変更された場合、THE App SHALL 設定を保存し、リアルタイムセクションの表示/非表示を切り替える

### 要件 20: 録音停止時のセクション制御（Section Control on Recording Stop）

**ユーザーストーリー:** ユーザーとして、録音停止後は文字起こしと要約に集中したい。

#### 受け入れ基準（Acceptance Criteria）

1. WHEN 録音が停止された場合、THE App SHALL 入力セクションとリアルタイム文字起こしセクションを折りたたみ、音声文字起こしセクションと要約セクションを展開する

### 要件 21: リアルタイム言語再判別（Realtime Language Re-detection）

**ユーザーストーリー:** ユーザーとして、リアルタイム文字起こし中に言語の再判別を手動でトリガーしたい。

#### 受け入れ基準（Acceptance Criteria）

1. THE App SHALL 言語自動判別モード時に、検出言語バッジの隣に緑色の更新アイコン（&#xE72C;、色 #16C60C）の再判別ボタンを表示する
2. WHEN ユーザーが再判別ボタンをクリックした場合、THE App SHALL リアルタイムストリーミングを再接続して言語判別をリセットする
3. WHEN 言語選択が自動判別以外に変更された場合、THE App SHALL 再判別ボタンと検出言語バッジを非表示にする
