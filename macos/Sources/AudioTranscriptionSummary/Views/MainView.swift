// MainView.swift
// 上部: 入力（録音コントロール）、下部: 折りたたみ可能な文字起こし・翻訳セクション

import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var awsSettingsViewModel: AWSSettingsViewModel
    @StateObject private var realtimeVM = RealtimeTranscriptionViewModel()
    @StateObject private var realtimeTranslationVM = TranslationViewModel()
    @StateObject private var transcriptTranslationVM = TranslationViewModel()
    @StateObject private var summaryTranslationVM = TranslationViewModel()

    @State private var showSettings = false
    @State private var isRealtimeExpanded = true
    @State private var isTranscriptExpanded = true
    @State private var isSummaryExpanded = true
    @State private var showSummaryFileImporter = false

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
    private var isRetryable: Bool {
        guard let op = viewModel.lastOperation else { return false }
        switch op { case .transcription, .summarization: return true; default: return false }
    }
    private var isAnyCapturing: Bool {
        viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            inputArea
            Divider()
            outputArea.layoutPriority(1)
            Divider()
            StatusBarView(viewModel: viewModel)
        }
        .frame(minWidth: 900, minHeight: 700)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) { AWSSettingsView(viewModel: awsSettingsViewModel) }
        .onAppear {
            // 起動時に AWS 接続テスト → 失敗なら設定画面を開く
            Task {
                await awsSettingsViewModel.testConnection()
                if !awsSettingsViewModel.connectionTestSuccess {
                    showSettings = true
                }
            }
        }
        .alert("エラー", isPresented: showErrorAlert) {
            if isRetryable {
                Button("再試行") { Task { await viewModel.retry() } }
                Button("閉じる", role: .cancel) { viewModel.errorMessage = nil }
            } else {
                Button("閉じる", role: .cancel) { viewModel.errorMessage = nil }
            }
        } message: { Text(viewModel.errorMessage ?? "") }
        .onAppear { realtimeVM.realtimeTranslationVM = realtimeTranslationVM }
        .onChange(of: viewModel.isCapturingSystemAudio) { _, v in handleCaptureChange(v) }
        .onChange(of: viewModel.isRecordingScreen) { _, v in handleCaptureChange(v) }
        .onChange(of: viewModel.transcript) { _, _ in transcriptTranslationVM.reset() }
        .onChange(of: viewModel.summary) { _, _ in summaryTranslationVM.reset() }
        .onChange(of: viewModel.isTranscribing) { _, transcribing in
            if transcribing {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isInputExpanded = false
                    isRealtimeExpanded = false
                }
            }
        }
    }

    // MARK: - ツールバー（左から: 録音/停止 → キャンセル → エクスポート → 設定）

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 録音/停止ボタン
        ToolbarItem(placement: .primaryAction) {
            if isAnyCapturing {
                Button {
                    Task {
                        if viewModel.isRecordingScreen { await viewModel.stopScreenRecording() }
                        else { await viewModel.stopSystemAudioCapture() }
                    }
                } label: { Image(systemName: "stop.circle.fill").foregroundStyle(.red).font(.title3) }
                    .help("停止")
                    .disabled(viewModel.isStoppingCapture)
            } else {
                Button {
                    Task {
                        if viewModel.selectedAudioSource.isScreenRecording { await viewModel.startScreenRecording() }
                        else { await viewModel.startSystemAudioCapture() }
                    }
                } label: { Image(systemName: "mic.circle.fill").foregroundStyle(.red).font(.title3) }
                    .help(viewModel.selectedAudioSource.isScreenRecording ? "録画開始" : "録音開始")
                    .disabled(viewModel.isStartingCapture || viewModel.isProcessing)
            }
        }
        // キャンセルボタン
        ToolbarItem(placement: .primaryAction) {
            if isAnyCapturing {
                Button {
                    Task {
                        if viewModel.isRecordingScreen { await viewModel.cancelScreenRecording() }
                        else { await viewModel.cancelSystemAudioCapture() }
                    }
                } label: { Image(systemName: "xmark.circle").font(.title3) }
                    .help("キャンセル")
                    .disabled(viewModel.isStoppingCapture)
            }
        }
        // 設定（右端）
        ToolbarItem(placement: .primaryAction) {
            Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
                .disabled(isAnyCapturing || viewModel.isProcessing)
        }
    }

    // MARK: - 上部: 入力（折りたたみ可能）

    @State private var isInputExpanded = true

    private var inputArea: some View {
        VStack(spacing: 0) {
            collapsibleSection(title: "入力", icon: "square.and.arrow.down", isExpanded: $isInputExpanded) {
                VStack(spacing: 8) {
                    // 1行目: 音源選択（左）+ レベルメーター（右）
                    HStack(spacing: 8) {
                        Picker("", selection: $viewModel.selectedAudioSource) {
                            ForEach(viewModel.availableAudioSources) { source in
                                Label(source.displayName, systemImage: source.iconName).tag(source)
                            }
                        }
                        .frame(width: 220)
                        .disabled(viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen || viewModel.isProcessing)
                        .onChange(of: viewModel.selectedAudioSource) { _, newSource in
                            if !newSource.isScreenRecording {
                                Task { await viewModel.startLevelPreview() }
                            } else {
                                Task { await viewModel.stopLevelPreview() }
                            }
                        }

                        if !viewModel.selectedAudioSource.isScreenRecording {
                            levelGauge(level: (viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen) ? viewModel.captureAudioLevel : viewModel.previewAudioLevel)
                        }
                    }

                    // 2行目: ファイル分割時間
                    HStack(spacing: 6) {
                        Text("ファイル分割")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $viewModel.splitIntervalMinutes) {
                            ForEach([1, 5, 10, 15, 20, 30, 45, 60], id: \.self) { min in
                                Text("\(min)分").tag(min)
                            }
                        }
                        .frame(width: 80)
                        .disabled(viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen)
                        .onChange(of: viewModel.splitIntervalMinutes) { _, newVal in
                            let store = AppSettingsStore()
                            var s = store.load()
                            s.splitIntervalMinutes = newVal
                            try? store.save(s)
                        }
                        Spacer()
                    }

                    // 3行目: リアルタイム文字起こしトグル
                    HStack(spacing: 6) {
                        Toggle(isOn: $awsSettingsViewModel.isRealtimeEnabled) {
                            EmptyView()
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(viewModel.isProcessing)
                        Text("リアルタイム文字起こし")
                            .font(.caption)
                            .onChange(of: awsSettingsViewModel.isRealtimeEnabled) { _, enabled in
                                awsSettingsViewModel.saveRealtimeSetting()
                                if enabled {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isRealtimeExpanded = true
                                        isTranscriptExpanded = false
                                        isSummaryExpanded = false
                                    }
                                    if isAnyCapturing {
                                        Task {
                                            await realtimeVM.startStreaming()
                                            viewModel.setRealtimeAudioCallback { [weak realtimeVM] buffer in realtimeVM?.sendAudioBuffer(buffer) }
                                        }
                                    }
                                } else {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isRealtimeExpanded = false
                                        isTranscriptExpanded = true
                                        isSummaryExpanded = true
                                    }
                                    realtimeVM.stopStreaming()
                                    viewModel.setRealtimeAudioCallback(nil)
                                    realtimeVM.finalText = ""
                                    realtimeVM.partialText = ""
                                    realtimeVM.detectedLanguage = nil
                                    realtimeVM.errorMessage = nil
                                    realtimeTranslationVM.reset()
                                }
                            }
                        Spacer()
                    }

                    // 画面プレビュー（画面録画中のみ）
                    if viewModel.isRecordingScreen, let frame = viewModel.screenPreviewFrame {
                        Image(decorative: frame, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.red.opacity(0.5), lineWidth: 1))
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
                .opacity(viewModel.isProcessing ? 0.5 : 1.0)
                .task { await viewModel.refreshAudioSources() }
            } statusContent: {
                EmptyView()
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - 下部: 出力

    private var outputArea: some View {
        VStack(spacing: 0) {
                // リアルタイム文字起こし（設定で無効の場合は非表示）
                if awsSettingsViewModel.isRealtimeEnabled {
                    collapsibleSection(title: "リアルタイム文字起こし", icon: "waveform.badge.mic", isExpanded: $isRealtimeExpanded) {
                        HStack(spacing: 0) {
                            TranscriptionPreviewPanel(viewModel: realtimeVM).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            TranslationPanel(sourceText: realtimeVM.finalText, autoTranslate: true, translationVM: realtimeTranslationVM).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 100)
                    } statusContent: {
                        // 検出言語ラベルは TranscriptionPreviewPanel 内に移動済み
                        EmptyView()
                    }
                    Divider()
                }

                collapsibleSection(title: "音声文字起こし", icon: "waveform", isExpanded: $isTranscriptExpanded) {
                    VStack(spacing: 0) {
                        FileDropZone(viewModel: viewModel, onFileSelected: {
                            // ファイル選択時: 入力とリアルタイムを閉じる
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInputExpanded = false
                                isRealtimeExpanded = false
                            }
                        }, isDisabled: isAnyCapturing || viewModel.isProcessing).padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
                        // ファイルリスト（ファイルがある場合のみ表示）
                        if !viewModel.fileList.isEmpty {
                            FileListView(viewModel: viewModel)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .disabled(isAnyCapturing || viewModel.isProcessing)
                                .opacity(isAnyCapturing || viewModel.isProcessing ? 0.5 : 1.0)
                        }
                        AudioPlayerView(viewModel: viewModel)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .disabled(isAnyCapturing || viewModel.isProcessing)
                            .opacity(isAnyCapturing || viewModel.isProcessing ? 0.5 : 1.0)
                        Divider()
                        HStack(spacing: 0) {
                            TranscriptView(viewModel: viewModel).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            TranslationPanel(sourceText: viewModel.transcript?.text ?? "", translationVM: transcriptTranslationVM).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 200)
                        .disabled(isAnyCapturing || viewModel.isProcessing)
                        .opacity(isAnyCapturing || viewModel.isProcessing ? 0.5 : 1.0)
                    }
                }
                Divider()
                collapsibleSection(title: "要約", icon: "doc.text", isExpanded: $isSummaryExpanded) {
                    VStack(spacing: 0) {
                        // 基盤モデル選択 + プロンプト + ボタン
                        VStack(alignment: .leading, spacing: 4) {
                            // 基盤モデル Picker（左寄せ）
                            HStack(spacing: 4) {
                                Picker("", selection: $awsSettingsViewModel.bedrockModelId) {
                                    ForEach(BedrockModel.availableModels(for: awsSettingsViewModel.region)) { model in
                                        Text("\(model.name)").tag(model.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 200)
                                .disabled(viewModel.isSummarizing || viewModel.isProcessing)
                                .onChange(of: awsSettingsViewModel.bedrockModelId) { _, _ in
                                    awsSettingsViewModel.saveBedrockModelSetting()
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.top, 4)

                            HStack(spacing: 6) {
                                TextEditor(text: $viewModel.summaryAdditionalPrompt)
                                    .font(.caption)
                                    .frame(height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color(.separatorColor), lineWidth: 1)
                                    )
                                    .overlay(alignment: .topLeading) {
                                        if viewModel.summaryAdditionalPrompt.isEmpty {
                                            Text("追加プロンプト（例: 箇条書きで要約して）")
                                                .font(.caption).foregroundStyle(.tertiary)
                                                .padding(.horizontal, 4).padding(.top, 6)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                VStack(spacing: 4) {
                                    Button {
                                        showSummaryFileImporter = true
                                    } label: {
                                        Label("ファイルから要約", systemImage: "doc.text")
                                            .font(.caption).frame(maxWidth: .infinity)
                                    }
                                    .controlSize(.small)
                                    .disabled(isAnyCapturing || viewModel.isProcessing)
                                    Button {
                                        Task { await viewModel.resummarize() }
                                    } label: {
                                        Label("要約", systemImage: "text.magnifyingglass")
                                            .font(.caption).frame(maxWidth: .infinity)
                                    }
                                    .disabled(viewModel.transcript == nil || viewModel.isSummarizing || viewModel.isProcessing)
                                    .controlSize(.small)
                                }
                                .frame(width: 110)
                            }
                            .padding(.horizontal, 8).padding(.bottom, 4)
                        }
                        .fileImporter(isPresented: $showSummaryFileImporter, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in
                            if case .success(let urls) = result, let url = urls.first {
                                // ファイル選択時: 入力とリアルタイムを閉じる
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isInputExpanded = false
                                    isRealtimeExpanded = false
                                }
                                let accessed = url.startAccessingSecurityScopedResource()
                                Task {
                                    await viewModel.summarizeFromFile(url: url)
                                    if accessed { url.stopAccessingSecurityScopedResource() }
                                }
                            }
                        }
                        Divider()
                        HStack(spacing: 0) {
                            SummaryView(viewModel: viewModel).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            TranslationPanel(sourceText: viewModel.summary?.text ?? "", translationVM: summaryTranslationVM).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 80)
                    }
                }
            }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - 折りたたみ（ステータス表示対応）

    private func collapsibleSection<Content: View>(title: String, icon: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        collapsibleSection(title: title, icon: icon, isExpanded: isExpanded, content: content) { EmptyView() }
    }

    private func collapsibleSection<Content: View, Status: View>(title: String, icon: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder statusContent: () -> Status) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right").font(.caption).foregroundColor(.secondary)
                    Image(systemName: icon).foregroundColor(.accentColor).font(.subheadline)
                    Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                    Spacer()
                    statusContent()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded.wrappedValue { Divider(); content() }
        }
    }

    // MARK: - 録音状態変更

    private func levelGauge(level: Float) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color(.separatorColor).opacity(0.3))
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > 0.8 ? .red : level > 0.5 ? .yellow : .green)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 6)
    }

    private func handleCaptureChange(_ capturing: Bool) {
        if capturing {
            // 録音開始: 入力とリアルタイムを展開、音声文字起こしと要約を閉じる
            withAnimation(.easeInOut(duration: 0.2)) {
                isInputExpanded = true
                isRealtimeExpanded = true
                isTranscriptExpanded = false
                isSummaryExpanded = false
            }

            realtimeVM.finalText = ""; realtimeVM.partialText = ""
            realtimeVM.detectedLanguage = nil; realtimeVM.errorMessage = nil
            realtimeVM.streamOutputPath = nil
            realtimeTranslationVM.reset(); transcriptTranslationVM.reset(); summaryTranslationVM.reset()
            viewModel.transcript = nil; viewModel.summary = nil; viewModel.audioFile = nil

            // リアルタイム文字起こしのストリーム出力パスを設定
            let saveDir = AWSSettingsViewModel.recordingDirectory
            let dateStr = {
                let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
                f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: Date())
            }()
            realtimeVM.streamOutputPath = saveDir.appendingPathComponent("\(dateStr).transcribe.stream.txt")

            if awsSettingsViewModel.isRealtimeEnabled {
                Task { await realtimeVM.startStreaming() }
                viewModel.setRealtimeAudioCallback { [weak realtimeVM] buffer in realtimeVM?.sendAudioBuffer(buffer) }
            }
        } else if !isAnyCapturing {
            // 録音終了: 音声文字起こしと要約を展開
            withAnimation(.easeInOut(duration: 0.2)) {
                isTranscriptExpanded = true
                isSummaryExpanded = true
            }

            realtimeVM.stopStreaming()
            realtimeVM.streamOutputPath = nil
            if let af = viewModel.audioFile, let t = realtimeVM.toTranscript(audioFileId: af.id) { viewModel.transcript = t }
            viewModel.setRealtimeAudioCallback(nil)
        }
    }

}
