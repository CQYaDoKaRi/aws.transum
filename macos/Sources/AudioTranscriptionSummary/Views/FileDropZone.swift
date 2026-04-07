// FileDropZone.swift
// ファイル読み込みエリア（D&D + ファイル追加）
// 常にドロップゾーンを表示し、ファイルはリストに登録するのみ

import SwiftUI
import UniformTypeIdentifiers

struct FileDropZone: View {
    @ObservedObject var viewModel: AppViewModel
    /// ファイル選択時に呼ばれるコールバック（折りたたみ連動用）
    var onFileSelected: (() -> Void)?
    /// 無効状態（録音中など）
    var isDisabled: Bool = false
    @State private var isFileImporterPresented = false
    @State private var isDragOver = false

    private static let supportedTypes: [UTType] = [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(isDragOver ? Color.accentColor : .secondary)

            Text("ドラッグ＆ドロップで対応ファイルをアップロード")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button { isFileImporterPresented = true } label: {
                Label("ファイル追加", systemImage: "plus").font(.caption2)
            }
            .controlSize(.small)
            .disabled(isDisabled)
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
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { isDisabled ? false : handleDrop(providers: $0) }
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: Self.supportedTypes, allowsMultipleSelection: true) { handleFileImporterResult($0) }
        .keyboardShortcut("o", modifiers: .command)
        .opacity(isDisabled ? 0.5 : 1.0)
    }

    // MARK: - ハンドラ

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        var loadedCount = 0
        let total = providers.count
        nonisolated(unsafe) var urls: [URL] = []
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                if let urlData = data as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    urls.append(url)
                }
                loadedCount += 1
                if loadedCount == total {
                    let capturedURLs = urls
                    Task { @MainActor [weak viewModel] in
                        guard let viewModel = viewModel else { return }
                        onFileSelected?()
                        await viewModel.addFilesToList(capturedURLs)
                    }
                }
            }
        }
        return true
    }

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let accessedURLs = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        Task { @MainActor in
            onFileSelected?()
            await viewModel.addFilesToList(urls)
            for (url, accessed) in accessedURLs {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
        }
    }
}
