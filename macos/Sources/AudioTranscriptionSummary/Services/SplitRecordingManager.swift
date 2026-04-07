// SplitRecordingManager.swift
// 録音ファイルの1分分割を管理するクラス
// 60秒ごとに録音ファイルを確定し、新しいファイルで録音を再開する

import Foundation

/// 録音ファイルの1分分割を管理するクラス
final class SplitRecordingManager {

    // MARK: - プロパティ

    /// 分割間隔（秒）。デフォルト60秒
    let splitInterval: TimeInterval

    /// 現在の連番（1始まり）
    private(set) var currentIndex: Int = 0

    /// 生成された分割ファイルの URL 一覧
    private(set) var splitFiles: [URL] = []

    /// ベースファイル名（タイムスタンプ部分。例: "20250101_120000"）
    let baseName: String

    /// 保存先ディレクトリ
    let outputDirectory: URL

    /// ファイル拡張子（デフォルト "m4a"）
    let fileExtension: String

    /// 分割タイマー（DispatchSourceTimer でバックグラウンドスレッド動作）
    private var splitTimer: DispatchSourceTimer?

    /// タイマー用のディスパッチキュー
    private let timerQueue = DispatchQueue(label: "SplitRecordingManager.timer", qos: .userInitiated)

    // MARK: - イニシャライザ

    /// SplitRecordingManager を初期化する
    /// - Parameters:
    ///   - baseName: ベースファイル名（タイムスタンプ部分）
    ///   - outputDirectory: 保存先ディレクトリ
    ///   - fileExtension: ファイル拡張子（デフォルト "m4a"）
    ///   - splitInterval: 分割間隔（秒、デフォルト60秒）
    init(baseName: String, outputDirectory: URL, fileExtension: String = "m4a", splitInterval: TimeInterval = 60) {
        self.baseName = baseName
        self.outputDirectory = outputDirectory
        self.fileExtension = fileExtension
        self.splitInterval = splitInterval
    }

    // MARK: - ファイル名生成

    /// 3桁ゼロ埋め連番付きファイル名を生成する
    /// - Parameter index: 連番（1始まり）
    /// - Returns: ファイル名（例: "20250101_120000-001.m4a"）
    func generateFileName(index: Int) -> String {
        let paddedIndex = String(format: "%03d", index)
        return "\(baseName)-\(paddedIndex).\(fileExtension)"
    }

    /// 次の分割ファイルの URL を生成し、currentIndex をインクリメント、splitFiles に追加する
    /// - Returns: 次の分割ファイルの URL
    func nextFileURL() -> URL {
        currentIndex += 1
        let fileName = generateFileName(index: currentIndex)
        let fileURL = outputDirectory.appendingPathComponent(fileName)
        splitFiles.append(fileURL)
        return fileURL
    }

    // MARK: - 分割タイマー制御

    /// 録音分割を開始する（DispatchSourceTimer でバックグラウンドスレッド動作）
    /// - Parameter onSplit: 分割時に呼ばれるコールバック（次のファイルURLを渡す）
    func startSplitting(onSplit: @escaping (URL) -> Void) {
        stopSplitting()

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + splitInterval, repeating: splitInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let nextURL = self.nextFileURL()
            onSplit(nextURL)
        }
        timer.resume()
        splitTimer = timer
    }

    /// 録音分割タイマーを停止する
    func stopSplitting() {
        splitTimer?.cancel()
        splitTimer = nil
    }

    /// 連番とファイル一覧をリセットする
    func reset() {
        stopSplitting()
        currentIndex = 0
        splitFiles = []
    }
}
