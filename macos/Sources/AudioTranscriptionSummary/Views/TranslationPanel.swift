// TranslationPanel.swift
// 翻訳パネル（言語 Picker + コピーボタン同一ライン + スクロールテキスト）

import SwiftUI
import AppKit

struct TranslationPanel: View {
    let sourceText: String
    var autoTranslate: Bool = false
    @ObservedObject var translationVM: TranslationViewModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー: 言語 Picker + 翻訳ボタン + コピーボタン（同一ライン）
            HStack(spacing: 6) {
                Picker("", selection: $translationVM.selectedTargetLanguage) {
                    ForEach(TranslationLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .onChange(of: translationVM.selectedTargetLanguage) { _, newLang in
                    if !sourceText.isEmpty {
                        Task { await translationVM.changeLanguageAndTranslate(newLang, text: sourceText) }
                    }
                }

                if !autoTranslate {
                    Button {
                        Task { await translationVM.translate(sourceText) }
                    } label: { Image(systemName: "globe") }
                    .disabled(sourceText.isEmpty || translationVM.isTranslating)
                    .help("翻訳")
                }

                if translationVM.isTranslating {
                    ProgressView().controlSize(.mini)
                }

                Spacer()

                // コピーボタン（右寄せ）
                if !translationVM.translatedText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(translationVM.translatedText, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Label(copied ? "コピー済み" : "コピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // 翻訳結果テキスト（スクロール、固定領域内）
            ScrollView(.vertical, showsIndicators: true) {
                if !translationVM.translatedText.isEmpty {
                    Text(translationVM.translatedText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.bottom, 4)
                } else {
                    ContentUnavailableView {
                        Label("翻訳結果", systemImage: "globe").font(.caption)
                    } description: { EmptyView() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let error = translationVM.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal, 8).padding(.bottom, 2)
            }
        }
    }
}
