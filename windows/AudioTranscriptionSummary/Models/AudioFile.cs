using System;

namespace AudioTranscriptionSummary.Models;

public record AudioFile(
    Guid Id,
    string FilePath,
    string FileName,
    string Extension,
    TimeSpan Duration,
    long FileSize,
    DateTime CreatedAt
);
