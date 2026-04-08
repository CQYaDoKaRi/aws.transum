// WaveformView.swift
// 波形表示ビュー
// Canvas を使用して波形バーを描画し、再生位置をクリック/ドラッグで操作可能にする

import SwiftUI

/// 波形表示ビュー
/// 再生済み部分と未再生部分を色分けして描画し、タップ/ドラッグでシーク操作を提供する
struct WaveformView: View {
    /// 波形データ（0.0〜1.0 の正規化された振幅値）
    let waveformData: [Float]
    /// 音声の総再生時間（秒）
    let duration: TimeInterval
    /// 現在の再生位置（秒）
    let currentTime: TimeInterval
    /// シーク操作コールバック
    let onSeek: (TimeInterval) -> Void

    /// バーの幅（pt）
    private let barWidth: CGFloat = 2
    /// バー間の間隔（pt）
    private let barSpacing: CGFloat = 1

    var body: some View {
        HStack(spacing: 8) {
            // 現在の再生位置（mm:ss）
            Text(formatTime(currentTime))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)

            // 波形描画エリア
            GeometryReader { geo in
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let seekTime = timeForPosition(x: value.location.x, width: geo.size.width)
                            onSeek(seekTime)
                        }
                )
                .onTapGesture { location in
                    let seekTime = timeForPosition(x: location.x, width: geo.size.width)
                    onSeek(seekTime)
                }
            }
            .frame(height: 40)

            // 総再生時間（mm:ss）
            Text(formatTime(duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
    }

    // MARK: - 波形描画

    /// Canvas に波形バーを描画する
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        guard !waveformData.isEmpty, duration > 0 else { return }

        let totalBarWidth = barWidth + barSpacing
        let barCount = min(waveformData.count, Int(size.width / totalBarWidth))
        guard barCount > 0 else { return }

        // 再生済みバーの割合
        let progress = currentTime / duration
        let playedBarCount = Int(Double(barCount) * progress)

        for i in 0..<barCount {
            let dataIndex = i * waveformData.count / barCount
            let amplitude = CGFloat(waveformData[dataIndex])
            let barHeight = max(amplitude * size.height, 1)
            let x = CGFloat(i) * totalBarWidth
            let y = (size.height - barHeight) / 2

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let color: Color = i < playedBarCount ? .accentColor : .gray.opacity(0.4)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
        }
    }

    // MARK: - ユーティリティ

    /// x 座標から再生時間を計算する
    /// - Parameters:
    ///   - x: タップ/ドラッグの x 座標
    ///   - width: 波形描画エリアの幅
    /// - Returns: 対応する再生時間（秒）。[0, duration] にクランプ
    private func timeForPosition(x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0, duration > 0 else { return 0 }
        let ratio = max(0, min(1, x / width))
        return ratio * duration
    }

    /// 秒数を mm:ss 形式にフォーマットする
    /// - Parameter time: 時間（秒）
    /// - Returns: フォーマットされた文字列（例: "03:45"）
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(time, 0))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
