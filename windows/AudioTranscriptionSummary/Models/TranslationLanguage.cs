// TranslationLanguage.cs
// 翻訳先言語の列挙型（macOS 版と共通）

namespace AudioTranscriptionSummary.Models;

public enum TranslationLanguage
{
    Japanese,
    English,
    Chinese,
    Korean,
    French,
    German,
    Spanish
}

public static class TranslationLanguageExtensions
{
    public static string ToCode(this TranslationLanguage lang) => lang switch
    {
        TranslationLanguage.Japanese => "ja",
        TranslationLanguage.English => "en",
        TranslationLanguage.Chinese => "zh",
        TranslationLanguage.Korean => "ko",
        TranslationLanguage.French => "fr",
        TranslationLanguage.German => "de",
        TranslationLanguage.Spanish => "es",
        _ => "ja"
    };

    public static string ToDisplayName(this TranslationLanguage lang) => lang switch
    {
        TranslationLanguage.Japanese => "日本語",
        TranslationLanguage.English => "English",
        TranslationLanguage.Chinese => "中文",
        TranslationLanguage.Korean => "한국어",
        TranslationLanguage.French => "Français",
        TranslationLanguage.German => "Deutsch",
        TranslationLanguage.Spanish => "Español",
        _ => "日本語"
    };
}
