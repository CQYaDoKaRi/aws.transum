// AudioPlayerView.swift
// 音声ファイルの再生コントロールビュー
// 再生/一時停止ボタンと波形表示を提供する

import SwiftUI

/// 音声再生コントロールを提供するビュー
/// 再生/一時停止ボタンと WaveformView による波形表示・シーク操作を含む
struct AudioPlayerView: View {
    /// アプリケーション全体の状態を管理する ViewModel
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        if let audioFile = viewModel.audioFile {
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

                // 波形表示（Slider の代替）
                WaveformView(
                    waveformData: viewModel.waveformData,
                    duration: audioFile.duration,
                    currentTime: viewModel.playbackPosition,
                    onSeek: { time in viewModel.seek(to: time) }
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.separatorColor).opacity(0.2))
        }
    }
}
