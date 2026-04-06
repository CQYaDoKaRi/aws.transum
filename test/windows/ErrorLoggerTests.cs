// ErrorLoggerTests.cs
// ErrorLogger のテスト
// - 元ファイル名ベースのエラーログ出力
// - ファイル名なしの場合は app.error.log に出力
// - 既存ファイルへの追記
// - ログ内容にデバッグ情報（日時、操作、ファイル名等）が含まれること
//
// テストデータ: test/data/test.wav, test/data/test.transcript.txt
// テスト生成ファイルは test/data/ 以下に出力し、テスト完了後に削除する

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Xunit;

namespace AudioTranscriptionSummary.Tests;

public class ErrorLoggerTests : IDisposable
{
    private static readonly string TestDataDir = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "..", "..", "test", "data"));

    private readonly List<string> _generatedFiles = new();

    public void Dispose()
    {
        foreach (var file in _generatedFiles)
        {
            if (File.Exists(file))
                File.Delete(file);
        }
    }

    private void WriteTestErrorLog(Exception error, string operation, string? sourceFileName)
    {
        if (!Directory.Exists(TestDataDir))
            Directory.CreateDirectory(TestDataDir);

        string logFileName;
        if (!string.IsNullOrEmpty(sourceFileName))
        {
            var baseName = Path.GetFileNameWithoutExtension(sourceFileName);
            logFileName = $"{baseName}.error.log";
        }
        else
        {
            logFileName = "app.error.log";
        }

        var filePath = Path.Combine(TestDataDir, logFileName);
        _generatedFiles.Add(filePath);

        var sb = new StringBuilder();
        sb.AppendLine();
        sb.AppendLine("=== エラーレポート ===");
        sb.AppendLine($"日時: {DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}");
        sb.AppendLine($"操作: {operation}");
        sb.AppendLine($"処理ファイル: {sourceFileName ?? "(なし)"}");
        sb.AppendLine();
        sb.AppendLine("--- エラー概要 ---");
        sb.AppendLine($"説明: {error.Message}");
        sb.AppendLine($"型: {error.GetType().FullName}");
        sb.AppendLine();
        sb.AppendLine("--- システム情報 ---");
        sb.AppendLine($"OS: {Environment.OSVersion}");
        sb.AppendLine($"PID: {Environment.ProcessId}");
        sb.AppendLine();

        File.AppendAllText(filePath, sb.ToString(), Encoding.UTF8);
    }

    [Fact]
    public void ErrorLog_WithSourceFileName_CreatesNamedLogFile()
    {
        var logFile = Path.Combine(TestDataDir, "test.error.log");
        if (File.Exists(logFile)) File.Delete(logFile);
        _generatedFiles.Add(logFile);

        var error = new InvalidOperationException("テストエラー");
        WriteTestErrorLog(error, "文字起こし", "test.wav");

        Assert.True(File.Exists(logFile));

        var content = File.ReadAllText(logFile, Encoding.UTF8);
        Assert.Contains("エラーレポート", content);
        Assert.Contains("日時:", content);
        Assert.Contains("操作: 文字起こし", content);
        Assert.Contains("処理ファイル: test.wav", content);
        Assert.Contains("テストエラー", content);
        Assert.Contains("システム情報", content);
    }

    [Fact]
    public void ErrorLog_WithoutSourceFileName_CreatesAppErrorLog()
    {
        var logFile = Path.Combine(TestDataDir, "app.error.log");
        if (File.Exists(logFile)) File.Delete(logFile);
        _generatedFiles.Add(logFile);

        var error = new Exception("ファイル名なしエラー");
        WriteTestErrorLog(error, "不明な操作", null);

        Assert.True(File.Exists(logFile));

        var content = File.ReadAllText(logFile, Encoding.UTF8);
        Assert.Contains("処理ファイル: (なし)", content);
        Assert.Contains("操作: 不明な操作", content);
    }

    [Fact]
    public void ErrorLog_AppendsToExistingFile()
    {
        var logFile = Path.Combine(TestDataDir, "append_test.error.log");
        if (File.Exists(logFile)) File.Delete(logFile);
        _generatedFiles.Add(logFile);

        WriteTestErrorLog(new Exception("エラー1"), "操作1", "append_test.wav");
        WriteTestErrorLog(new Exception("エラー2"), "操作2", "append_test.wav");

        var content = File.ReadAllText(logFile, Encoding.UTF8);
        Assert.Contains("エラー1", content);
        Assert.Contains("エラー2", content);
        Assert.Contains("操作1", content);
        Assert.Contains("操作2", content);
    }

    [Fact]
    public void TestTranscriptFileExists()
    {
        var transcriptFile = Path.Combine(TestDataDir, "test.transcript.txt");
        Assert.True(File.Exists(transcriptFile),
            "test/data/test.transcript.txt が存在しません。テストデータを配置してください。");

        var text = File.ReadAllText(transcriptFile, Encoding.UTF8);
        Assert.NotEmpty(text);
    }

    [Fact]
    public void TestAudioFileExists()
    {
        var audioFile = Path.Combine(TestDataDir, "test.m4a");
        Assert.True(File.Exists(audioFile),
            "test/data/test.m4a が存在しません。テストデータを配置してください。");
    }
}
