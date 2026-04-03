// SystemAudioCaptureView.swift
// 音源選択とレベルメーターのみ表示（録音/停止/キャンセルはツールバーに統合済み）

import SwiftUI

struct SystemAudioCaptureView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    private var isAnyCapturing: Bool {
        viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen
    }

    var body: some View {
        VStack(spacing: 8) {
            // 音源選択 Picker（画面録画を含む）
            Picker("", selection: $viewModel.selectedAudioSource) {
                ForEach(viewModel.availableAudioSources) { source in
                    Label(source.displayName, systemImage: source.iconName).tag(source)
                }
            }
            .disabled(isAnyCapturing)
            .onChange(of: viewModel.selectedAudioSource) { _, newSource in
                if !newSource.isScreenRecording {
                    Task { await viewModel.startLevelPreview() }
                } else {
                    Task { await viewModel.stopLevelPreview() }
                }
            }

            // レベルメーター（録音中 or プレビュー中、画面録画以外）
            if !viewModel.selectedAudioSource.isScreenRecording {
                levelGauge(level: isAnyCapturing ? viewModel.captureAudioLevel : viewModel.previewAudioLevel)
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
        .task { await viewModel.refreshAudioSources() }
        .onChange(of: viewModel.isCapturingSystemAudio) { _, capturing in
            if capturing { startTimer() } else { stopTimer() }
        }
        .onChange(of: viewModel.isRecordingScreen) { _, recording in
            if recording { startTimer() } else { stopTimer() }
        }
    }

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

    private var currentLevel: Float {
        viewModel.isCapturingSystemAudio ? viewModel.captureAudioLevel : viewModel.screenRecordingAudioLevel
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0)); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func startTimer() {
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in elapsedTime += 1 }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil; elapsedTime = 0 }
}
