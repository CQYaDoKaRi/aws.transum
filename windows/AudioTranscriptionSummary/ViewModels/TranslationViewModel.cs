#nullable enable
using System;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using AudioTranscriptionSummary.Models;
using AudioTranscriptionSummary.Services;

namespace AudioTranscriptionSummary.ViewModels;

public partial class TranslationViewModel : ObservableObject
{
    private readonly TranslateService _translateService;

    [ObservableProperty] private string _translatedText = "";
    [ObservableProperty] private TranslationLanguage _selectedTargetLanguage = TranslationLanguage.Japanese;
    [ObservableProperty] private bool _isTranslating;
    [ObservableProperty] private string? _errorMessage;

    public TranslationViewModel(TranslateService translateService)
    {
        _translateService = translateService;
    }

    [RelayCommand]
    public async Task TranslateAsync(string? sourceText)
    {
        if (string.IsNullOrWhiteSpace(sourceText)) return;
        TranslatedText = "";
        IsTranslating = true;
        ErrorMessage = null;
        try
        {
            var targetCode = SelectedTargetLanguage.ToCode();
            TranslatedText = await _translateService.TranslateTextAsync(
                sourceText, targetCode, CancellationToken.None);
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
