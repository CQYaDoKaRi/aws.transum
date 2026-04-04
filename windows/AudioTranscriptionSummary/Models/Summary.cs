using System;

namespace AudioTranscriptionSummary.Models;

public record Summary(
    Guid Id,
    Guid TranscriptId,
    string Text,
    DateTime CreatedAt
);
