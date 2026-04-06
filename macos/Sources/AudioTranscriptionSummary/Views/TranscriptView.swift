// TranscriptView.swift
// 文字起こし + 要約の統合ビュー
// 1つのボタンで文字起こし→要約→自動エクスポートを実行する

import SwiftUI

struct TranscriptView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedLanguage: TranscriptionLanguage = .auto

    /// 処理中かどうか
    private var isProcessing: Bool {
        viewModel.isTranscribing || viewModel.isSummarizing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ツールバー
            HStack {
                Picker("言語", selection: $selectedLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Spacer()

                // 文字起こし + 要約 統合ボタン
                Button {
                    Task {
                        await viewModel.transcribeAndSummarize(language: selectedLanguage)
                    }
                } label: {
                    Label("文字起こし＋要約", systemImage: "waveform.and.doc")
                }
                .disabled(viewModel.audioFile == nil || isProcessing)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            // 結果表示
            if let transcript = viewModel.transcript {
                CopyableTextView(
                    text: transcript.text,
                    placeholder: "文字起こし結果",
                    icon: "text.alignleft"
                )

                // エクスポートファイルパス表示
                if let path = viewModel.lastTranscriptPath {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            } else if !isProcessing {
                ContentUnavailableView {
                    Label("文字起こし結果", systemImage: "text.alignleft")
                } description: { EmptyView() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
