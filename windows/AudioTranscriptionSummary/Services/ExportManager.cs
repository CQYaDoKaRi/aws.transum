#nullable enable
using System;
using System.IO;
using System.Text;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

public class ExportManager
{
    public bool CanWrite(string directory)
    {
        try
        {
            if (!Directory.Exists(directory))
                return false;

            var testPath = Path.Combine(directory, $".write_test_{Guid.NewGuid()}");
            File.WriteAllText(testPath, "");
            File.Delete(testPath);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public void Export(Transcript transcript, Summary? summary, string directory)
    {
        if (!CanWrite(directory))
        {
            throw new AppError(
                AppErrorType.WritePermissionDenied,
                "保存先に書き込み権限がありません");
        }

        var baseName = DateTime.Now.ToString("yyyyMMdd_HHmmss");

        // Export transcript
        var transcriptPath = Path.Combine(directory, $"{baseName}.transcript.txt");
        var transcriptContent = $"=== Transcript ==={Environment.NewLine}{transcript.Text}";
        File.WriteAllText(transcriptPath, transcriptContent, Encoding.UTF8);

        // Export summary if available
        if (summary != null)
        {
            var summaryPath = Path.Combine(directory, $"{baseName}.summary.txt");
            var summaryContent = $"=== Summary ==={Environment.NewLine}{summary.Text}";
            File.WriteAllText(summaryPath, summaryContent, Encoding.UTF8);
        }
    }
}
