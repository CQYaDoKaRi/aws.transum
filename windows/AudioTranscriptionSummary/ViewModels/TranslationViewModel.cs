// TranslationViewModel.cs
// 翻訳パネル用 ViewModel（macOS 版と同じ設計）

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.ViewModels;

public partial class TranslationViewModel : ObservableObject
{
    [ObservableProperty] private string _translatedText = "";
    [ObservableProperty] private TranslationLanguage _selectedTargetLanguage = TranslationLanguage.Japanese;
    [ObservableProperty] private bool _isTranslating;
    [ObservableProperty] private string? _errorMessage;

    [RelayCommand]
    private async Task TranslateAsync(string sourceText)
    {
        if (string.IsNullOrWhiteSpace(sourceText)) return;
        TranslatedText = "";
        IsTranslating = true;
        ErrorMessage = null;
        try
        {
            // TODO: AWS SDK for .NET の TranslateClient を使用
            TranslatedText = $"[翻訳結果: {SelectedTargetLanguage.ToDisplayName()}]";
        }
        catch (Exception ex)
        {
            ErrorMessage = $"翻訳エラー: {ex.Message}";
        }
        finally
        {
            IsTranslating = false;
        }
    }

    public void Reset()
    {
        TranslatedText = "";
        ErrorMessage = null;
    }
}
