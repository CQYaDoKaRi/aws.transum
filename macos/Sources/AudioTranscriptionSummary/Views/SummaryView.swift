// SummaryView.swift
// 要約結果の表示ビュー
// 要約は TranscriptView の統合ボタンから自動実行される

import SwiftUI

struct SummaryView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 結果表示
            if let summary = viewModel.summary {
                CopyableTextView(
                    text: summary.text,
                    placeholder: "要約結果",
                    icon: "doc.text"
                )

                // エクスポートファイルパス表示
                if let path = viewModel.lastSummaryPath {
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
            } else if viewModel.transcript == nil {
                ContentUnavailableView {
                    Label("要約結果", systemImage: "doc.text")
                } description: {
                    Text("文字起こし＋要約を実行してください")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isSummarizing {
                VStack {
                    ProgressView()
                    Text("要約を生成中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("要約結果", systemImage: "doc.text")
                } description: {
                    Text("要約の生成を待っています")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
