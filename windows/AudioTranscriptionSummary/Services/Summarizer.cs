using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using AudioTranscriptionSummary.Models;

namespace AudioTranscriptionSummary.Services;

public class Summarizer
{
    public const int MinimumCharacterCount = 50;

    private static readonly char[] SentenceDelimiters = { '。', '！', '？', '.', '!', '?' };

    public Summary Summarize(Transcript transcript)
    {
        if (transcript.Text.Length < MinimumCharacterCount)
        {
            throw new AppError(
                AppErrorType.InsufficientContent,
                "要約するには内容が不十分です");
        }

        var sentences = SplitSentences(transcript.Text);
        if (sentences.Count == 0)
        {
            throw new AppError(
                AppErrorType.InsufficientContent,
                "要約するには内容が不十分です");
        }

        var wordFrequencies = CalculateWordFrequencies(sentences);
        var scores = new List<(int Index, double Score)>();

        for (int i = 0; i < sentences.Count; i++)
        {
            double freqScore = CalculateFrequencyScore(sentences[i], wordFrequencies);
            double posScore = CalculatePositionScore(i, sentences.Count);
            double lenScore = CalculateLengthScore(sentences[i], sentences);
            double totalScore = freqScore + posScore + lenScore;
            scores.Add((i, totalScore));
        }

        int selectCount = Math.Max(1, (int)Math.Round(sentences.Count * 0.3));
        var topIndices = scores
            .OrderByDescending(s => s.Score)
            .Take(selectCount)
            .Select(s => s.Index)
            .OrderBy(i => i) // preserve original order
            .ToList();

        var summaryText = string.Join("", topIndices.Select(i => sentences[i]));

        return new Summary(
            Id: Guid.NewGuid(),
            TranscriptId: transcript.Id,
            Text: summaryText,
            CreatedAt: DateTime.Now);
    }

    private static List<string> SplitSentences(string text)
    {
        var sentences = new List<string>();
        var pattern = @"[^。！？.!?]*[。！？.!?]";
        var matches = Regex.Matches(text, pattern);

        foreach (Match match in matches)
        {
            var sentence = match.Value.Trim();
            if (!string.IsNullOrWhiteSpace(sentence))
                sentences.Add(sentence);
        }

        // If no delimiters found, treat entire text as one sentence
        if (sentences.Count == 0 && !string.IsNullOrWhiteSpace(text))
            sentences.Add(text.Trim());

        return sentences;
    }

    private static Dictionary<string, int> CalculateWordFrequencies(List<string> sentences)
    {
        var freq = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var sentence in sentences)
        {
            var words = Regex.Split(sentence, @"[\s\p{P}]+")
                .Where(w => !string.IsNullOrWhiteSpace(w));
            foreach (var word in words)
            {
                freq.TryGetValue(word, out int count);
                freq[word] = count + 1;
            }
        }
        return freq;
    }

    private static double CalculateFrequencyScore(string sentence, Dictionary<string, int> frequencies)
    {
        var words = Regex.Split(sentence, @"[\s\p{P}]+")
            .Where(w => !string.IsNullOrWhiteSpace(w))
            .ToList();

        if (words.Count == 0) return 0;

        int maxFreq = frequencies.Values.Max();
        if (maxFreq == 0) return 0;

        double sum = words.Sum(w => frequencies.TryGetValue(w, out int f) ? (double)f / maxFreq : 0);
        return sum / words.Count;
    }

    private static double CalculatePositionScore(int index, int total)
    {
        if (total <= 1) return 1.0;
        if (index == 0) return 1.0;
        if (index == total - 1) return 0.5;

        // Linear decrease from 1.0 to 0.5 for middle sentences
        return 1.0 - (0.5 * index / (total - 1));
    }

    private static double CalculateLengthScore(string sentence, List<string> allSentences)
    {
        if (allSentences.Count == 0) return 0;

        double avgLength = allSentences.Average(s => s.Length);
        if (avgLength == 0) return 0;

        // Sentences closer to average length score higher
        double ratio = sentence.Length / avgLength;
        return ratio > 1.0 ? 1.0 / ratio : ratio;
    }
}
