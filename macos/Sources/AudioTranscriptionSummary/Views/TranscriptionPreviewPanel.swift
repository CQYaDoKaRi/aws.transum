// TranscriptionPreviewPanel.swift
// リアルタイム文字起こしプレビュー（言語セレクタ・コピーボタン付き、固定高さスクロール）

import SwiftUI
import AppKit

struct TranscriptionPreviewPanel: View {
    @ObservedObject var viewModel: RealtimeTranscriptionViewModel
    @State private var copied = false

    private var fullText: String {
        let final = viewModel.finalText
        let partial = viewModel.partialText
        if partial.isEmpty { return final }
        return final.isEmpty ? partial : final + partial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 言語セレクタ（上部）
            languageSelector

            // コピーボタン（テキストがある場合のみ）
            if !fullText.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullText, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "コピー済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .padding(.trailing, 8).padding(.top, 4)
                }
            }

            // テキスト表示（固定高さスクロール）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !viewModel.finalText.isEmpty {
                            Text(viewModel.finalText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !viewModel.partialText.isEmpty {
                            Text(viewModel.partialText)
                                .italic().foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 8).padding(.bottom, 4)
                }
                .onChange(of: viewModel.finalText) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: viewModel.partialText) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            }

            if let error = viewModel.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal, 8).padding(.bottom, 2)
            }
        }
    }

    // MARK: - 言語セレクタ

    /// 言語ラベル + Picker + 検出言語ラベル + 再判別ボタンを表示する
    private var languageSelector: some View {
        HStack(spacing: 6) {
            // 言語 Picker（auto 含む全言語）
            Picker("", selection: $viewModel.selectedLanguage) {
                ForEach(TranscriptionLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .frame(width: 160)

            // 検出言語ラベル + 再判別ボタン（自動検出モード時）
            if viewModel.selectedLanguage == .auto {
                if let detected = viewModel.detectedLanguage {
                    Text(detected)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // 再判別ボタン
                Button {
                    Task { await viewModel.restartStreamingWithNewLanguage() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("言語を再判別")
                .disabled(!viewModel.isStreaming)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // 言語変更時にストリーミングを再接続
        .onChange(of: viewModel.selectedLanguage) { _, _ in
            Task { await viewModel.restartStreamingWithNewLanguage() }
        }
    }
}
