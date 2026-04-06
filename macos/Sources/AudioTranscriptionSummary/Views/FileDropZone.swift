// FileDropZone.swift
// ファイル読み込みエリア（D&D + ファイル選択）
// 未選択時: コンパクトな点線枠、選択後: ファイル情報表示

import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    @ObservedObject var viewModel: AppViewModel
    /// ファイル選択時に呼ばれるコールバック（折りたたみ連動用）
    var onFileSelected: (() -> Void)?
    @State private var isFileImporterPresented = false
    @State private var isDragOver = false

    private static let supportedTypes: [UTType] = [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie]

    var body: some View {
        Group {
            if let audioFile = viewModel.audioFile {
                fileInfoView(audioFile: audioFile)
            } else {
                dropGuidanceView
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { handleDrop(providers: $0) }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: Self.supportedTypes, allowsMultipleSelection: false) { handleFileImporterResult($0) }
        .keyboardShortcut("o", modifiers: .command)
    }

    // MARK: - ファイル情報表示

    private func fileInfoView(audioFile: AudioFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: FileImporter.videoExtensions.contains(audioFile.fileExtension.lowercased()) ? "film" : "waveform")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(audioFile.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(audioFile.fileExtension.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(formatDuration(audioFile.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button { isFileImporterPresented = true } label: {
                Label("別のファイル", systemImage: "folder").font(.caption2)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color(.separatorColor),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 3])
                )
        )
    }

    // MARK: - ドロップゾーン（未選択時）

    private var dropGuidanceView: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(isDragOver ? Color.accentColor : .secondary)

            Text("ドラッグ＆ドロップで対応ファイルをアップロード")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button { isFileImporterPresented = true } label: {
                Label("ファイルを選択", systemImage: "folder").font(.caption2)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isDragOver ? Color.accentColor : Color(.separatorColor),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 3])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragOver ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }

    // MARK: - ハンドラ

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            guard let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
            Task { @MainActor in
                onFileSelected?()
                await viewModel.importFile(from: url)
            }
        }
        return true
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            onFileSelected?()
            await viewModel.importFile(from: url)
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let s = Int(duration); return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
