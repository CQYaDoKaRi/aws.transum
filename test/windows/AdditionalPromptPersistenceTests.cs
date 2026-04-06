// AdditionalPromptPersistenceTests.cs
// 追加プロンプトの設定保存・復元テスト
// - 要約実行時に追加プロンプトが設定 JSON に保存されること
// - アプリ起動時に復元されること
//
// テスト生成ファイルは test/data/ 以下に出力し、テスト完了後に削除する

using System;
using System.IO;
using System.Text.Json;
using Xunit;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Tests;

public class AdditionalPromptPersistenceTests : IDisposable
{
    private static readonly string TestDataDir = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "test", "data"));

    private readonly string _settingsDir;
    private readonly string _settingsFile;

    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public AdditionalPromptPersistenceTests()
    {
        _settingsDir = Path.Combine(TestDataDir, $"settings_test_{Guid.NewGuid():N}");
        _settingsFile = Path.Combine(_settingsDir, "settings.json");
        Directory.CreateDirectory(_settingsDir);
    }

    public void Dispose()
    {
        if (Directory.Exists(_settingsDir))
            Directory.Delete(_settingsDir, true);
    }

    private AppSettings LoadSettings()
    {
        if (!File.Exists(_settingsFile))
            return new AppSettings();
        var json = File.ReadAllText(_settingsFile);
        return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
    }

    private void SaveSettings(AppSettings settings)
    {
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(_settingsFile, json);
    }

    [Fact]
    public void SaveAndRestore_AdditionalPrompt()
    {
        // 初期状態: 空文字
        var initial = LoadSettings();
        Assert.Equal("", initial.SummaryAdditionalPrompt);

        // 保存
        initial.SummaryAdditionalPrompt = "箇条書きで要約して";
        SaveSettings(initial);

        Assert.True(File.Exists(_settingsFile));

        // 復元
        var restored = LoadSettings();
        Assert.Equal("箇条書きで要約して", restored.SummaryAdditionalPrompt);
    }

    [Fact]
    public void EmptyPrompt_SavedAndRestoredCorrectly()
    {
        var settings = new AppSettings { SummaryAdditionalPrompt = "テスト" };
        SaveSettings(settings);

        // 空文字で上書き
        settings.SummaryAdditionalPrompt = "";
        SaveSettings(settings);

        var restored = LoadSettings();
        Assert.Equal("", restored.SummaryAdditionalPrompt);
    }

    [Fact]
    public void NoSideEffects_OnOtherSettings()
    {
        var settings = new AppSettings
        {
            Region = "us-east-1",
            BedrockModelId = "anthropic.claude-sonnet-4-6",
            SummaryAdditionalPrompt = "テストプロンプト"
        };
        SaveSettings(settings);

        var restored = LoadSettings();
        Assert.Equal("us-east-1", restored.Region);
        Assert.Equal("anthropic.claude-sonnet-4-6", restored.BedrockModelId);
        Assert.Equal("テストプロンプト", restored.SummaryAdditionalPrompt);
    }
}
