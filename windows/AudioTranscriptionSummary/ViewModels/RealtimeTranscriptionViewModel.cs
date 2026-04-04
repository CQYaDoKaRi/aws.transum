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

    public void AppendFinalTranscript(string text)
    {
        if (string.IsNullOrEmpty(text)) return;
        FinalText += (FinalText.Length > 0 ? " " : "") + text;
        PartialText = "";
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
    }
}
