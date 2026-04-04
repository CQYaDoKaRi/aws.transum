using System;

namespace AudioTranscriptionSummary.Models;

public enum AppErrorType
{
    UnsupportedFormat,
    CorruptedFile,
    TranscriptionFailed,
    SilentAudio,
    SummarizationFailed,
    InsufficientContent,
    ExportFailed,
    WritePermissionDenied,
    CredentialsNotSet
}

public class AppError : Exception
{
    public AppErrorType ErrorType { get; }

    public bool IsRetryable => ErrorType is
        AppErrorType.TranscriptionFailed or AppErrorType.SummarizationFailed;

    public AppError(AppErrorType errorType, string message)
        : base(message)
    {
        ErrorType = errorType;
    }

    public AppError(AppErrorType errorType, string message, Exception innerException)
        : base(message, innerException)
    {
        ErrorType = errorType;
    }
}
