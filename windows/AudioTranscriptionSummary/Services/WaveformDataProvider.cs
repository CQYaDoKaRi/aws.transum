#nullable enable
using System;
using NAudio.Wave;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// 波形描画用のサンプルデータを提供する
/// 音声ファイルからサンプルを読み込み、ダウンサンプリングして正規化した配列を返す
/// </summary>
public static class WaveformDataProvider
{
    /// <summary>
    /// 音声ファイルから波形データを抽出する
    /// </summary>
    /// <param name="filePath">音声ファイルのパス</param>
    /// <param name="sampleCount">出力するサンプル数（描画解像度、デフォルト: 200）</param>
    /// <returns>正規化された振幅値の配列（0.0〜1.0）。エラー時は空配列を返す</returns>
    public static float[] LoadWaveformData(string filePath, int sampleCount = 200)
    {
        if (sampleCount <= 0) return Array.Empty<float>();

        try
        {
            using var reader = new AudioFileReader(filePath);
            var totalSamples = (int)(reader.Length / (reader.WaveFormat.BitsPerSample / 8));
            if (totalSamples <= 0) return Array.Empty<float>();

            // 全サンプルを読み込む
            var buffer = new float[totalSamples];
            int samplesRead = reader.Read(buffer, 0, totalSamples);
            if (samplesRead <= 0) return Array.Empty<float>();

            int channels = reader.WaveFormat.Channels;
            int frameCount = samplesRead / channels;
            if (frameCount <= 0) return Array.Empty<float>();

            // 全フレームを sampleCount 個のビンに分割し、各ビンの最大振幅を取得
            var amplitudes = new float[sampleCount];

            for (int bin = 0; bin < sampleCount; bin++)
            {
                int start = bin * frameCount / sampleCount;
                int end = Math.Min((bin + 1) * frameCount / sampleCount, frameCount);
                if (start >= end) continue;

                float maxAmplitude = 0;
                for (int i = start; i < end; i++)
                {
                    // 全チャンネルの最大振幅を取得
                    for (int ch = 0; ch < channels; ch++)
                    {
                        float sample = Math.Abs(buffer[i * channels + ch]);
                        if (sample > maxAmplitude)
                            maxAmplitude = sample;
                    }
                }
                amplitudes[bin] = maxAmplitude;
            }

            // 全体の最大値で正規化（0.0〜1.0）
            float globalMax = 0;
            for (int i = 0; i < amplitudes.Length; i++)
            {
                if (amplitudes[i] > globalMax)
                    globalMax = amplitudes[i];
            }

            if (globalMax > 0)
            {
                for (int i = 0; i < amplitudes.Length; i++)
                {
                    amplitudes[i] /= globalMax;
                }
            }

            return amplitudes;
        }
        catch
        {
            // エラー時は空配列を返す
            return Array.Empty<float>();
        }
    }
}
