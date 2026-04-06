// ErrorLogger.cs
// エラー発生時に詳細情報をファイルに保存するサービス
// 元ファイル名.error.log に追記、ファイル名がない場合は app.error.log に追記

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
    /// <summary>
    /// ログ出力先ディレクトリを返す
    /// </summary>
    private static string GetLogDirectory()
    {
        var settings = new SettingsStore().Load();
        var dir = !string.IsNullOrEmpty(settings.ExportDirectoryPath)
            ? settings.ExportDirectoryPath
            : !string.IsNullOrEmpty(settings.RecordingDirectoryPath)
                ? settings.RecordingDirectoryPath
                : Path.Combine(Path.GetTempPath(), "AudioTranscriptionSummary");

        if (!Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        return dir;
    }

    /// <summary>
    /// 元ファイル名からログファイルパスを決定する
    /// </summary>
    private static string GetLogFilePath(string? sourceFileName)
    {
        var dir = GetLogDirectory();
        if (!string.IsNullOrEmpty(sourceFileName))
        {
            var baseName = Path.GetFileNameWithoutExtension(sourceFileName);
            return Path.Combine(dir, $"{baseName}.error.log");
        }
        return Path.Combine(dir, "app.error.log");
    }

    /// <summary>
    /// エラーレポートをログファイルに追記する
    /// </summary>
    /// <param name="error">発生した例外</param>
    /// <param name="operation">実行中の操作名</param>
    /// <param name="sourceFileName">処理中の元ファイル名（null の場合は app.error.log に出力）</param>
    /// <param name="context">追加のコンテキスト情報</param>
    public static void SaveErrorLog(Exception error, string operation, string? sourceFileName = null, Dictionary<string, string>? context = null)
    {
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine();
            sb.AppendLine("=== エラーレポート ===");
            sb.AppendLine($"日時: {DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}");
            sb.AppendLine($"操作: {operation}");
            sb.AppendLine($"処理ファイル: {sourceFileName ?? "(なし)"}");
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

            File.AppendAllText(GetLogFilePath(sourceFileName), sb.ToString(), Encoding.UTF8);
        }
        catch
        {
            // ログ書き込み自体の失敗は無視
        }
    }
}
