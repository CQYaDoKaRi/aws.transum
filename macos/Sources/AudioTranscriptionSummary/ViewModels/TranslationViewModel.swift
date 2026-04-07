// TranslationViewModel.swift
// 翻訳パネル用の軽量 ViewModel
// 各翻訳パネル（リアルタイム・文字起こし・要約）で独立したインスタンスを使用

import Foundation

@MainActor
class TranslationViewModel: ObservableObject {
    @Published var translatedText: String = ""
    @Published var selectedTargetLanguage: TranslationLanguage = .japanese
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?

    private let translateService = TranslateService()

    /// テキストを翻訳する
    func translate(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        translatedText = ""
        isTranslating = true
        errorMessage = nil
        do {
            translatedText = try await translateService.translate(
                text: text,
                from: "auto",
                to: selectedTargetLanguage.rawValue,
                region: AWSSettingsViewModel.currentRegion
            )
        } catch {
            errorMessage = "翻訳エラー: \(error.localizedDescription)"
        }
        isTranslating = false
    }

    /// 翻訳先言語を変更して再翻訳する
    func changeLanguageAndTranslate(_ language: TranslationLanguage, text: String) async {
        selectedTargetLanguage = language
        await translate(text)
    }

    /// 表示テキストの最大行数
    private let maxDisplayLines = 500

    /// リアルタイム翻訳: 確定テキストを追記翻訳する
    func translateAppend(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isTranslating = true
        do {
            let translated = try await translateService.translate(
                text: text,
                from: "auto",
                to: selectedTargetLanguage.rawValue,
                region: AWSSettingsViewModel.currentRegion
            )
            translatedText += translated + "\n"
            translatedText = trimToMaxLines(translatedText)
        } catch {
            errorMessage = "翻訳エラー: \(error.localizedDescription)"
        }
        isTranslating = false
    }

    /// テキストを最大行数に制限する（超過分は先頭から削除）
    private func trimToMaxLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxDisplayLines {
            return lines.suffix(maxDisplayLines).joined(separator: "\n")
        }
        return text
    }

    /// 状態をリセットする
    func reset() {
        translatedText = ""
        errorMessage = nil
    }
}
