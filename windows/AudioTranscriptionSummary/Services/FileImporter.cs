using System;
using System.Collections.Generic;
using System.IO;
using AudioTranscriptionSummary.Models;
using NAudio.Wave;

namespace AudioTranscriptionSummary.Services;

public class FileImporter
{
    public static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ".m4a", ".wav", ".mp3", ".aiff", ".mp4", ".mov", ".m4v"
        };

    public bool IsSupported(string extension)
    {
        return SupportedExtensions.Contains(extension);
    }

    public AudioFile Import(string filePath)
    {
        var fileInfo = new FileInfo(filePath);
        var extension = fileInfo.Extension.ToLowerInvariant();

        if (!IsSupported(extension))
        {
            throw new AppError(
                AppErrorType.UnsupportedFormat,
                $"サポート対象外の形式です。対応形式: {string.Join(", ", SupportedExtensions)}");
        }

        TimeSpan duration;
        try
        {
            using var reader = new AudioFileReader(filePath);
            duration = reader.TotalTime;
        }
        catch (Exception ex)
        {
            throw new AppError(
                AppErrorType.CorruptedFile,
                "ファイルが読み込めません",
                ex);
        }

        return new AudioFile(
            Id: Guid.NewGuid(),
            FilePath: filePath,
            FileName: fileInfo.Name,
            Extension: extension,
            Duration: duration,
            FileSize: fileInfo.Length,
            CreatedAt: DateTime.Now);
    }
}
