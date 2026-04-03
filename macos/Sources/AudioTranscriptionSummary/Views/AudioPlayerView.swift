// AudioPlayerView.swift
// 音声ファイルの再生コントロールビュー
// 再生/一時停止ボタン、シークバー、時間表示を提供する

import SwiftUI

/// 音声再生コントロールを提供するビュー
/// 再生/一時停止ボタン、シークバーによる再生位置表示・操作、
/// 現在位置と総再生時間の mm:ss 形式表示を含む
struct AudioPlayerView: View {
    /// アプリケーション全体の状態を管理する ViewModel
    @ObservedObject var viewModel: AppViewModel

    /// シークバーのドラッグ中かどうか
    @State private var isDragging = false

    /// ドラッグ中の一時的なシーク位置
    @State private var dragPosition: TimeInterval = 0

    var body: some View {
        if let audioFile = viewModel.audioFile {
            // 音声ファイルが読み込まれている場合: 再生コントロールを表示
            HStack(spacing: 12) {
                // 再生/一時停止ボタン
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)

                // 現在の再生位置（mm:ss）
                Text(formatTime(isDragging ? dragPosition : viewModel.playbackPosition))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                // シークバー
                Slider(
                    value: Binding(
                        get: { isDragging ? dragPosition : viewModel.playbackPosition },
                        set: { newValue in
                            dragPosition = newValue
                            isDragging = true
                        }
                    ),
                    in: 0...max(audioFile.duration, 0.01)
                ) { editing in
                    // ドラッグ終了時にシーク実行
                    if !editing {
                        viewModel.seek(to: dragPosition)
                        isDragging = false
                    }
                }

                // 総再生時間（mm:ss）
                Text(formatTime(audioFile.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.separatorColor).opacity(0.2))
        }
    }

    // MARK: - ユーティリティ

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
