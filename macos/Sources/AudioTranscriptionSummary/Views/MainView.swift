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
    @State private var showSaveConfirmation = false
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
            StatusBarView()
        }
        .frame(minWidth: 900, minHeight: 700)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showSettings) { AWSSettingsView(viewModel: awsSettingsViewModel) }
        .alert("エラー", isPresented: showErrorAlert) {
            if isRetryable {
                Button("再試行") { Task { await viewModel.retry() } }
                Button("閉じる", role: .cancel) { viewModel.errorMessage = nil }
            } else {
                Button("閉じる", role: .cancel) { viewModel.errorMessage = nil }
            }
        } message: { Text(viewModel.errorMessage ?? "") }
        .alert("保存完了", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: { Text("保存しました") }
        .onAppear { realtimeVM.realtimeTranslationVM = realtimeTranslationVM }
        .onChange(of: viewModel.isCapturingSystemAudio) { _, v in handleCaptureChange(v) }
        .onChange(of: viewModel.isRecordingScreen) { _, v in handleCaptureChange(v) }
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
            } else {
                Button {
                    Task {
                        if viewModel.selectedAudioSource.isScreenRecording { await viewModel.startScreenRecording() }
                        else { await viewModel.startSystemAudioCapture() }
                    }
                } label: { Image(systemName: "mic.circle.fill").foregroundStyle(.red).font(.title3) }
                    .help(viewModel.selectedAudioSource.isScreenRecording ? "録画開始" : "録音開始")
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
            }
        }
        // エクスポート
        ToolbarItem(placement: .primaryAction) {
            EmptyView() // エクスポートは自動保存のため不要
        }
        // 設定（右端）
        ToolbarItem(placement: .primaryAction) {
            Button { showSettings = true } label: { Label("設定", systemImage: "gearshape") }
        }
    }

    // MARK: - 上部: 入力（折りたたみ可能）

    @State private var isInputExpanded = true

    private var inputArea: some View {
        VStack(spacing: 0) {
            collapsibleSection(title: "入力", icon: "square.and.arrow.down", isExpanded: $isInputExpanded) {
                SystemAudioCaptureView(viewModel: viewModel)
            } statusContent: {
                if viewModel.isCapturingSystemAudio {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("録音中").font(.caption2).foregroundStyle(.red)
                } else if viewModel.isRecordingScreen {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("録画中").font(.caption2).foregroundStyle(.red)
                }
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
                        // 言語判定ラベルのみ
                        if let lang = realtimeVM.detectedLanguage {
                            Text(lang).font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Divider()
                }

                collapsibleSection(title: "音声文字起こし", icon: "waveform", isExpanded: $isTranscriptExpanded) {
                    VStack(spacing: 0) {
                        FileDropZone(viewModel: viewModel) {
                            // ファイル選択時: 入力とリアルタイムを閉じる
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isInputExpanded = false
                                isRealtimeExpanded = false
                            }
                        }.padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
                        AudioPlayerView(viewModel: viewModel).padding(.horizontal, 8).padding(.vertical, 2)
                        Divider()
                        HStack(spacing: 0) {
                            TranscriptView(viewModel: viewModel).frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider()
                            TranslationPanel(sourceText: viewModel.transcript?.text ?? "", translationVM: transcriptTranslationVM).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 100)
                    }
                }
                Divider()
                collapsibleSection(title: "要約", icon: "doc.text", isExpanded: $isSummaryExpanded) {
                    VStack(spacing: 0) {
                        // 基盤モデル表示 + プロンプト + ボタン
                        VStack(alignment: .leading, spacing: 4) {
                            // 利用する基盤モデル表示
                            HStack(spacing: 4) {
                                Image(systemName: "cpu").font(.caption2).foregroundStyle(.secondary)
                                Text(BedrockModel.find(by: viewModel.awsSettingsBedrockModelId)?.name ?? "ローカル要約")
                                    .font(.caption2).foregroundStyle(.secondary)
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
                                    Button {
                                        Task { await viewModel.resummarize() }
                                    } label: {
                                        Label("要約", systemImage: "text.magnifyingglass")
                                            .font(.caption).frame(maxWidth: .infinity)
                                    }
                                    .disabled(viewModel.transcript == nil || viewModel.isSummarizing)
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
            realtimeTranslationVM.reset(); transcriptTranslationVM.reset(); summaryTranslationVM.reset()
            viewModel.transcript = nil; viewModel.summary = nil; viewModel.audioFile = nil
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
            if let af = viewModel.audioFile, let t = realtimeVM.toTranscript(audioFileId: af.id) { viewModel.transcript = t }
            viewModel.setRealtimeAudioCallback(nil)
        }
    }

    // MARK: - エクスポート

    private func exportResults() {
        guard viewModel.transcript != nil else { return }
        if let dir = AWSSettingsViewModel.exportDirectory {
            Task { await viewModel.exportResults(to: dir); if viewModel.errorMessage == nil { showSaveConfirmation = true } }
            return
        }
        let panel = NSSavePanel()
        panel.title = "エクスポート先を選択"
        panel.nameFieldStringValue = "\(viewModel.audioFile?.fileName ?? "transcript").transcript.txt"
        panel.allowedContentTypes = [.plainText]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.exportResults(to: url.deletingLastPathComponent()); if viewModel.errorMessage == nil { showSaveConfirmation = true } }
    }
}
