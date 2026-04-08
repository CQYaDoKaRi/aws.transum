// FileListView.swift
// 音声文字起こしセクション内のファイルリスト表示
// ヘッダー: 全選択チェックボックス + ファイル追加 + 削除ボタン
// 各行: チェックボックス + フォーマットバッジ + ファイル名 + 再生時間 + ファイルサイズ
// 行タップで音声プレーヤーの再生ファイルを切り替え

import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isFileImporterPresented = false

    private static let supportedTypes: [UTType] = [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie]

    private var selectedIds: Set<UUID> {
        Set(viewModel.fileList.filter { $0.isSelected }.map { $0.id })
    }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { viewModel.isAllSelected },
                    set: { _ in viewModel.toggleSelectAll() }
                )) {
                    Text("全選択")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                Button {
                    viewModel.removeFilesFromList(selectedIds)
                } label: {
                    Label("削除", systemImage: "trash").font(.caption2)
                }
                .controlSize(.small)
                .disabled(selectedIds.isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // ファイルリスト
            List {
                ForEach(viewModel.fileList.indices, id: \.self) { index in
                    fileRow(index: index)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .listRowBackground(
                            viewModel.audioFile?.id == viewModel.fileList[index].audioFile.id
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectFileForPlayback(viewModel.fileList[index].audioFile)
                        }
                }
            }
            .listStyle(.plain)
            .frame(maxHeight: min(CGFloat(viewModel.fileList.count) * 28 + 8, 200))
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let accessedURLs = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
                Task {
                    await viewModel.addFilesToList(urls)
                    for (url, accessed) in accessedURLs {
                        if accessed { url.stopAccessingSecurityScopedResource() }
                    }
                }
            }
        }
    }

    // MARK: - ファイル行

    private func fileRow(index: Int) -> some View {
        let item = viewModel.fileList[index]
        return HStack(spacing: 6) {
            Toggle(isOn: $viewModel.fileList[index].isSelected) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            // フォーマットバッジ
            Text(item.audioFile.fileExtension.uppercased())
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(formatColor(item.audioFile.fileExtension).opacity(0.15))
                .foregroundStyle(formatColor(item.audioFile.fileExtension))
                .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(item.audioFile.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(item.durationText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(item.fileSizeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    /// フォーマットに応じた色を返す
    private func formatColor(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "m4a", "aac": return .blue
        case "wav": return .green
        case "mp3": return .orange
        case "aiff": return .purple
        case "mp4", "mov", "m4v": return .red
        default: return .secondary
        }
    }
}
