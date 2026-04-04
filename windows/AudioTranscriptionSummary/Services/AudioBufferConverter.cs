#nullable enable
using System;
using System.IO;
using NAudio.Wave;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// NAudio WaveFormat → PCM 16kHz 16-bit signed LE mono 変換ユーティリティ
/// </summary>
public static class AudioBufferConverter
{
    private static readonly WaveFormat TargetFormat = new(16000, 16, 1);

    /// <summary>
    /// 任意のWaveFormatからPCM 16kHz 16-bit mono LEに変換する。
    /// </summary>
    public static byte[] ConvertToPcm16kHz(byte[] input, WaveFormat sourceFormat)
    {
        if (input == null || input.Length == 0)
            return Array.Empty<byte>();

        // Already in target format — return as-is
        if (sourceFormat.SampleRate == 16000 &&
            sourceFormat.BitsPerSample == 16 &&
            sourceFormat.Channels == 1 &&
            sourceFormat.Encoding == WaveFormatEncoding.Pcm)
        {
            return input;
        }

        using var inputStream = new RawSourceWaveStream(new MemoryStream(input), sourceFormat);
        using var resampler = new MediaFoundationResampler(inputStream, TargetFormat);
        resampler.ResamplerQuality = 60; // highest quality

        using var outputMs = new MemoryStream();
        var buffer = new byte[4096];
        int bytesRead;
        while ((bytesRead = resampler.Read(buffer, 0, buffer.Length)) > 0)
        {
            outputMs.Write(buffer, 0, bytesRead);
        }

        return outputMs.ToArray();
    }
}
