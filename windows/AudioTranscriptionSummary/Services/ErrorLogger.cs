// ErrorLogger.cs
// エラー発生時に詳細情報をファイルに保存するサービス
// ログは1ファイル（日付時刻.error.log）に集約する（Mac版と同じ形式）

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

public static class ErrorLogger
{
    private static readonly Lazy<string> _logFilePath = new(() =>
    {
        var settings = new SettingsStore().Load();
        var dir = !string.IsNullOrEmpty(settings.ExportDirectoryPath)
            ? settings.ExportDirectoryPath
            : !string.IsNullOrEmpty(settings.RecordingDirectoryPath)
                ? settings.RecordingDirectoryPath
                : Path.Combine(Path.GetTempPath(), "AudioTranscriptionSummary");

        if (!Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        var timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        return Path.Combine(dir, $"{timestamp}.error.log");
    });

    /// <summary>
    /// エラーレポートをログファイルに追記する
    /// </summary>
    public static void SaveErrorLog(Exception error, string operation, Dictionary<string, string>? context = null)
    {
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine();
            sb.AppendLine("=== エラーレポート ===");
            sb.AppendLine($"日時: {DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}");
            sb.AppendLine($"操作: {operation}");
            sb.AppendLine();

            // エラー概要
            sb.AppendLine("--- エラー概要 ---");
            sb.AppendLine($"説明: {error.Message}");
            sb.AppendLine($"型: {error.GetType().FullName}");
            sb.AppendLine();

            // AppError 詳細
            if (error is AppError appErr)
            {
                sb.AppendLine("--- AppError 詳細 ---");
                sb.AppendLine($"ErrorType: {appErr.ErrorType}");
                sb.AppendLine($"IsRetryable: {appErr.IsRetryable}");
                if (appErr.InnerException != null)
                {
                    sb.AppendLine($"InnerException: {appErr.InnerException.GetType().FullName}");
                    sb.AppendLine($"InnerMessage: {appErr.InnerException.Message}");
                }
                sb.AppendLine();
            }

            // InnerException チェーン
            var inner = error.InnerException;
            int depth = 0;
            while (inner != null && depth < 5)
            {
                sb.AppendLine($"--- InnerException [{depth}] ---");
                sb.AppendLine($"型: {inner.GetType().FullName}");
                sb.AppendLine($"メッセージ: {inner.Message}");
                inner = inner.InnerException;
                depth++;
            }
            sb.AppendLine();

            // スタックトレース
            sb.AppendLine("--- スタックトレース ---");
            if (!string.IsNullOrEmpty(error.StackTrace))
            {
                foreach (var line in error.StackTrace.Split('\n').Take(30))
                    sb.AppendLine(line.TrimEnd());
            }
            else
            {
                sb.AppendLine("(スタックトレースなし)");
            }
            sb.AppendLine();

            // コンテキスト
            sb.AppendLine("--- コンテキスト ---");
            if (context != null)
            {
                foreach (var kv in context.OrderBy(k => k.Key))
                    sb.AppendLine($"{kv.Key}: {kv.Value}");
            }
            else
            {
                sb.AppendLine("(なし)");
            }
            sb.AppendLine();

            // システム情報
            sb.AppendLine("--- システム情報 ---");
            sb.AppendLine($"OS: {Environment.OSVersion}");
            sb.AppendLine($".NET: {Environment.Version}");
            sb.AppendLine($"プロセス: {Process.GetCurrentProcess().ProcessName}");
            sb.AppendLine($"PID: {Environment.ProcessId}");
            sb.AppendLine($"メモリ: {Environment.WorkingSet / (1024 * 1024)} MB");
            sb.AppendLine($"CPU数: {Environment.ProcessorCount}");
            sb.AppendLine();

            File.AppendAllText(_logFilePath.Value, sb.ToString(), Encoding.UTF8);
        }
        catch
        {
            // ログ書き込み自体の失敗は無視
        }
    }
}
