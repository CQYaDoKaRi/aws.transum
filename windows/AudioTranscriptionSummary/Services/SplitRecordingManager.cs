#nullable enable
using System;
using System.Collections.Generic;
using System.Threading;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// 録音ファイルの1分分割を管理するクラス
/// 60秒ごとに録音ファイルを確定し、新しいファイルで録音を再開する
/// </summary>
public class SplitRecordingManager
{
    /// <summary>分割間隔（デフォルト60秒）</summary>
    public TimeSpan SplitInterval { get; }

    /// <summary>現在の連番（1始まり）</summary>
    public int CurrentIndex { get; private set; }

    /// <summary>生成された分割ファイルパス一覧</summary>
    public List<string> SplitFiles { get; } = new();

    /// <summary>ベースファイル名（タイムスタンプ部分。例: "20250101_120000"）</summary>
    public string BaseName { get; }

    /// <summary>保存先ディレクトリ</summary>
    public string OutputDirectory { get; }

    /// <summary>ファイル拡張子（デフォルト "wav"）</summary>
    public string FileExtension { get; }

    /// <summary>分割タイマー</summary>
    private Timer? _splitTimer;

    /// <summary>
    /// SplitRecordingManager を初期化する
    /// </summary>
    /// <param name="baseName">ベースファイル名（タイムスタンプ部分）</param>
    /// <param name="outputDirectory">保存先ディレクトリ</param>
    /// <param name="fileExtension">ファイル拡張子（デフォルト "wav"）</param>
    /// <param name="splitInterval">分割間隔（デフォルト60秒）</param>
    public SplitRecordingManager(
        string baseName,
        string outputDirectory,
        string fileExtension = "wav",
        TimeSpan? splitInterval = null)
    {
        BaseName = baseName;
        OutputDirectory = outputDirectory;
        FileExtension = fileExtension;
        SplitInterval = splitInterval ?? TimeSpan.FromSeconds(60);
    }

    /// <summary>
    /// 3桁ゼロ埋め連番付きファイル名を生成する
    /// </summary>
    /// <param name="index">連番（1始まり）</param>
    /// <returns>ファイル名（例: "20250101_120000-001.wav"）</returns>
    public string GenerateFileName(int index)
    {
        return $"{BaseName}-{index:D3}.{FileExtension}";
    }

    /// <summary>
    /// 次の分割ファイルのパスを生成し、CurrentIndex をインクリメント、SplitFiles に追加する
    /// </summary>
    /// <returns>次の分割ファイルのフルパス</returns>
    public string NextFilePath()
    {
        CurrentIndex++;
        var fileName = GenerateFileName(CurrentIndex);
        var filePath = System.IO.Path.Combine(OutputDirectory, fileName);
        SplitFiles.Add(filePath);
        return filePath;
    }

    /// <summary>
    /// 録音分割を開始する（タイマー起動）
    /// </summary>
    /// <param name="onSplit">分割時に呼ばれるコールバック（次のファイルパスを渡す）</param>
    public void StartSplitting(Action<string> onSplit)
    {
        StopSplitting();

        _splitTimer = new Timer(_ =>
        {
            var nextPath = NextFilePath();
            onSplit(nextPath);
        }, null, SplitInterval, SplitInterval);
    }

    /// <summary>
    /// 録音分割タイマーを停止する
    /// </summary>
    public void StopSplitting()
    {
        _splitTimer?.Dispose();
        _splitTimer = null;
    }

    /// <summary>
    /// 連番とファイル一覧をリセットする
    /// </summary>
    public void Reset()
    {
        StopSplitting();
        CurrentIndex = 0;
        SplitFiles.Clear();
    }
}
