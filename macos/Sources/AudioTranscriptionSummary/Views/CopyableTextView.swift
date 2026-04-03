// CopyableTextView.swift
// コピーボタン付きのテキスト表示コンポーネント

import SwiftUI
import AppKit

/// テキスト表示 + コピーボタンの共通コンポーネント
struct CopyableTextView: View {
    let text: String
    let placeholder: String
    let icon: String

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if !text.isEmpty {
                // コピーボタン
                HStack {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "コピー済み" : "コピー",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            } else {
                ContentUnavailableView {
                    Label(placeholder, systemImage: icon)
                        .font(.caption)
                } description: {
                    EmptyView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
