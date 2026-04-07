namespace AudioTranscriptionSummary.Models;

/// <summary>
/// 文字起こしに使用する言語（Amazon Transcribe 対応言語）
/// </summary>
public enum TranscriptionLanguage
{
    Auto,
    Japanese,
    English,
    Chinese,
    Korean,
    French,
    German,
    Spanish,
    Portuguese,
    Italian,
    Hindi,
    Arabic,
    Russian,
    Turkish,
    Dutch,
    Swedish,
    Polish,
    Thai,
    Indonesian,
    Vietnamese,
    Malay
}

public static class TranscriptionLanguageExtensions
{
    public static string ToCode(this TranscriptionLanguage lang) => lang switch
    {
        TranscriptionLanguage.Auto => "auto",
        TranscriptionLanguage.Japanese => "ja-JP",
        TranscriptionLanguage.English => "en-US",
        TranscriptionLanguage.Chinese => "zh-CN",
        TranscriptionLanguage.Korean => "ko-KR",
        TranscriptionLanguage.French => "fr-FR",
        TranscriptionLanguage.German => "de-DE",
        TranscriptionLanguage.Spanish => "es-ES",
        TranscriptionLanguage.Portuguese => "pt-BR",
        TranscriptionLanguage.Italian => "it-IT",
        TranscriptionLanguage.Hindi => "hi-IN",
        TranscriptionLanguage.Arabic => "ar-SA",
        TranscriptionLanguage.Russian => "ru-RU",
        TranscriptionLanguage.Turkish => "tr-TR",
        TranscriptionLanguage.Dutch => "nl-NL",
        TranscriptionLanguage.Swedish => "sv-SE",
        TranscriptionLanguage.Polish => "pl-PL",
        TranscriptionLanguage.Thai => "th-TH",
        TranscriptionLanguage.Indonesian => "id-ID",
        TranscriptionLanguage.Vietnamese => "vi-VN",
        TranscriptionLanguage.Malay => "ms-MY",
        _ => "auto"
    };

    public static string ToDisplayName(this TranscriptionLanguage lang) => lang switch
    {
        TranscriptionLanguage.Auto => "言語自動判定",
        TranscriptionLanguage.Japanese => "日本語",
        TranscriptionLanguage.English => "英語",
        TranscriptionLanguage.Chinese => "中国語",
        TranscriptionLanguage.Korean => "韓国語",
        TranscriptionLanguage.French => "フランス語",
        TranscriptionLanguage.German => "ドイツ語",
        TranscriptionLanguage.Spanish => "スペイン語",
        TranscriptionLanguage.Portuguese => "ポルトガル語",
        TranscriptionLanguage.Italian => "イタリア語",
        TranscriptionLanguage.Hindi => "ヒンディー語",
        TranscriptionLanguage.Arabic => "アラビア語",
        TranscriptionLanguage.Russian => "ロシア語",
        TranscriptionLanguage.Turkish => "トルコ語",
        TranscriptionLanguage.Dutch => "オランダ語",
        TranscriptionLanguage.Swedish => "スウェーデン語",
        TranscriptionLanguage.Polish => "ポーランド語",
        TranscriptionLanguage.Thai => "タイ語",
        TranscriptionLanguage.Indonesian => "インドネシア語",
        TranscriptionLanguage.Vietnamese => "ベトナム語",
        TranscriptionLanguage.Malay => "マレー語",
        _ => "言語自動判定"
    };
}
