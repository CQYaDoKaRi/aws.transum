#nullable enable
using System;
using CommunityToolkit.Mvvm.ComponentModel;

namespace AudioTranscriptionSummary.Models;

/// <summary>
/// 音声文字起こしセクションのファイルリストに表示する項目
/// AudioFile をラップし、選択状態と表示用プロパティを提供する
/// </summary>
public partial class FileListItem : ObservableObject
{
    /// <summary>一意な識別子</summary>
    public Guid Id { get; init; }

    /// <summary>音声ファイル情報</summary>
    public AudioFile AudioFile { get; init; }

    /// <summary>選択状態（チェックボックス用）</summary>
    [ObservableProperty] private bool _isSelected;

    /// <summary>再生時間の表示テキスト（"01:00" 形式）</summary>
    public string DurationText
    {
        get
        {
            var totalSeconds = (int)AudioFile.Duration.TotalSeconds;
            var minutes = totalSeconds / 60;
            var seconds = totalSeconds % 60;
            return $"{minutes:D2}:{seconds:D2}";
        }
    }

    /// <summary>ファイルサイズの表示テキスト（"1.2 MB" 形式）</summary>
    public string FileSizeText
    {
        get
        {
            var bytes = (double)AudioFile.FileSize;
            if (bytes >= 1_073_741_824)
                return $"{bytes / 1_073_741_824:F1} GB";
            if (bytes >= 1_048_576)
                return $"{bytes / 1_048_576:F1} MB";
            if (bytes >= 1024)
                return $"{bytes / 1024:F1} KB";
            return $"{(int)bytes} B";
        }
    }

    /// <summary>
    /// FileListItem を初期化する（isSelected はデフォルト true）
    /// </summary>
    public FileListItem(AudioFile audioFile, bool isSelected = true)
    {
        Id = Guid.NewGuid();
        AudioFile = audioFile;
        _isSelected = isSelected;
    }
}
