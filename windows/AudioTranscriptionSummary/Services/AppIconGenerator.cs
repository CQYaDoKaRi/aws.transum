#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;

namespace AudioTranscriptionSummary.Services;

/// <summary>
/// アプリアイコンを生成するヘルパー（波形＋ドキュメント＋Tデザイン）
/// macOS版と同じデザインをSystem.Drawingで再現する
/// </summary>
public static class AppIconGenerator
{
    private static readonly string IconCachePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "AudioTranscriptionSummary", "app.ico");

    /// <summary>
    /// アイコンファイルのパスを返す（未生成なら生成する）
    /// </summary>
    public static string GetIconPath()
    {
        if (File.Exists(IconCachePath))
            return IconCachePath;

        var dir = Path.GetDirectoryName(IconCachePath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);

        GenerateIcon(IconCachePath);
        return IconCachePath;
    }

    private static void GenerateIcon(string path)
    {
        const int size = 256;

        using var bmp = new Bitmap(size, size);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.HighQuality;
        g.TextRenderingHint = TextRenderingHint.AntiAliasAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;

        // 角丸背景（青グラデーション）
        var rect = new Rectangle(0, 0, size, size);
        var cornerRadius = (int)(size * 0.22);
        using var bgPath = CreateRoundedRect(rect, cornerRadius);

        using var gradBrush = new LinearGradientBrush(
            rect,
            Color.FromArgb(255, 26, 77, 191),   // 深い青
            Color.FromArgb(255, 51, 140, 242),   // 明るい青
            LinearGradientMode.Vertical);
        g.FillPath(gradBrush, bgPath);

        // 波形バー（白）
        var barColor = Color.FromArgb(240, 255, 255, 255);
        using var barBrush = new SolidBrush(barColor);
        float barWidth = 9;
        float barSpacing = 6;
        float[] barHeights = { 30, 50, 70, 90, 80, 100, 75, 60, 85, 65, 45, 30 };
        float totalWidth = barHeights.Length * barWidth + (barHeights.Length - 1) * barSpacing;
        float startX = (size - totalWidth) / 2;
        float centerY = size * 0.55f;

        for (int i = 0; i < barHeights.Length; i++)
        {
            float x = startX + i * (barWidth + barSpacing);
            float h = barHeights[i];
            float y = centerY - h / 2;
            using var barPath = CreateRoundedRect(
                new RectangleF(x, y, barWidth, h), barWidth / 2);
            g.FillPath(barBrush, barPath);
        }

        // ドキュメントアイコン（右下）
        float docX = size * 0.62f;
        float docY = size * 0.06f;
        float docW = size * 0.28f;
        float docH = size * 0.32f;
        using var docPath = CreateRoundedRect(
            new RectangleF(docX, docY, docW, docH), 4);
        using var docBrush = new SolidBrush(Color.FromArgb(230, 255, 255, 255));
        g.FillPath(docBrush, docPath);

        // ドキュメント内のテキスト行
        using var lineBrush = new SolidBrush(Color.FromArgb(180, 38, 102, 217));
        float lineH = 3;
        float lineMargin = 8;
        float[] lineWidths = { 0.8f, 0.65f, 0.75f, 0.5f };
        for (int i = 0; i < lineWidths.Length; i++)
        {
            float ly = docY + docH - lineMargin - i * (lineH + 5) - lineH;
            float lw = (docW - lineMargin * 2) * lineWidths[i];
            g.FillRectangle(lineBrush, docX + lineMargin, ly, lw, lineH);
        }

        // 「T」文字（左下）
        using var tFont = new Font("Segoe UI", size * 0.14f, FontStyle.Bold);
        using var tBrush = new SolidBrush(Color.FromArgb(220, 255, 255, 255));
        g.DrawString("T", tFont, tBrush, size * 0.08f, size * 0.68f);

        // ICOファイルとして保存
        SaveAsIco(bmp, path);
    }

    private static void SaveAsIco(Bitmap bmp, string path)
    {
        // ICOフォーマット: ヘッダー + エントリ + PNGデータ
        using var pngStream = new MemoryStream();
        bmp.Save(pngStream, System.Drawing.Imaging.ImageFormat.Png);
        var pngBytes = pngStream.ToArray();

        using var fs = new FileStream(path, FileMode.Create);
        using var bw = new BinaryWriter(fs);

        // ICOヘッダー
        bw.Write((short)0);       // Reserved
        bw.Write((short)1);       // Type: ICO
        bw.Write((short)1);       // Image count

        // ICOエントリ（256x256 PNG）
        bw.Write((byte)0);        // Width (0 = 256)
        bw.Write((byte)0);        // Height (0 = 256)
        bw.Write((byte)0);        // Color palette
        bw.Write((byte)0);        // Reserved
        bw.Write((short)1);       // Color planes
        bw.Write((short)32);      // Bits per pixel
        bw.Write(pngBytes.Length); // Data size
        bw.Write(22);             // Data offset (6 + 16)

        // PNGデータ
        bw.Write(pngBytes);
    }

    private static GraphicsPath CreateRoundedRect(RectangleF rect, float radius)
    {
        var path = new GraphicsPath();
        float d = radius * 2;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }
}
