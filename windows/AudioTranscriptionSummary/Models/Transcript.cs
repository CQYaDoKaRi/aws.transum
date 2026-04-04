using System;

namespace AudioTranscriptionSummary.Models;

public record Transcript(
    Guid Id,
    Guid AudioFileId,
    string Text,
    string Language,
    DateTime CreatedAt
);
