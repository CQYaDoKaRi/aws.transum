#nullable enable
using System;
using CommunityToolkit.Mvvm.ComponentModel;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.ViewModels;

public partial class RealtimeTranscriptionViewModel : ObservableObject
{
    [ObservableProperty] private string _finalText = "";
    [ObservableProperty] private string _partialText = "";
    [ObservableProperty] private string? _detectedLanguage;
    [ObservableProperty] private string? _errorMessage;

    /// リアルタイム文字起こしのストリーム出力先ファイルパス
    public string? StreamOutputPath { get; set; }

    private const int MaxDisplayLines = 500;

    public void AppendFinalTranscript(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        FinalText += (FinalText.Length > 0 ? " " : "") + text;
        FinalText = TrimToMaxLines(FinalText);
        PartialText = "";
        // ストリーム出力: 確定テキストをファイルに逐次追記
        AppendToStreamFile(text + "\n");
    }

    public void UpdatePartialTranscript(string text)
    {
        PartialText = text ?? "";
    }

    public Transcript? ToTranscript(Guid audioFileId)
    {
        var text = FinalText.Trim();
        if (string.IsNullOrEmpty(text)) return null;

        return new Transcript(
            Id: Guid.NewGuid(),
            AudioFileId: audioFileId,
            Text: text,
            Language: DetectedLanguage ?? "ja-JP",
            CreatedAt: DateTime.Now
        );
    }

    public void Reset()
    {
        FinalText = "";
        PartialText = "";
        DetectedLanguage = null;
        ErrorMessage = null;
        StreamOutputPath = null;
    }

    /// 確定テキストをストリーム出力ファイルに逐次追記する
    private void AppendToStreamFile(string text)
    {
        if (string.IsNullOrEmpty(StreamOutputPath)) return;
        try
        {
            System.IO.File.AppendAllText(StreamOutputPath, text, System.Text.Encoding.UTF8);
        }
        catch
        {
            // ストリーム出力の失敗は録音に影響させない
        }
    }

    /// テキストを最大行数に制限する（超過分は先頭から削除）
    private static string TrimToMaxLines(string text)
    {
        var lines = text.Split('\n');
        if (lines.Length > MaxDisplayLines)
        {
            return string.Join("\n", lines[^MaxDisplayLines..]);
        }
        return text;
    }
}
