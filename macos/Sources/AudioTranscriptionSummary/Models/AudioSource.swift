// AudioSource.swift
// 録音時の音源リソースを表すモデル

import Foundation
import ScreenCaptureKit
import AVFoundation

// MARK: - AudioSourceType（音源種別）

/// 録音時に選択可能な音源の種別
enum AudioSourceType: Hashable, Identifiable {
    /// システム全体の音声
    case systemAudio
    /// マイク入力
    case microphone(deviceID: String, name: String)
    /// 特定アプリケーションの音声
    case application(bundleID: String, name: String)
    /// 画面録画（動画＋音声）
    case screenRecording

    var id: String {
        switch self {
        case .systemAudio:
            return "system"
        case .microphone(let deviceID, _):
            return "mic-\(deviceID)"
        case .application(let bundleID, _):
            return "app-\(bundleID)"
        case .screenRecording:
            return "screen"
        }
    }

    var displayName: String {
        switch self {
        case .systemAudio:
            return "システム全体"
        case .microphone(_, let name):
            return "🎤 \(name)"
        case .application(_, let name):
            return name
        case .screenRecording:
            return "🖥 画面録画（動画＋音声）"
        }
    }

    var iconName: String {
        switch self {
        case .systemAudio:
            return "mic.fill"
        case .microphone:
            return "mic.fill"
        case .application:
            return "app.fill"
        case .screenRecording:
            return "record.circle"
        }
    }

    /// マイク入力かどうか
    var isMicrophone: Bool {
        if case .microphone = self { return true }
        return false
    }

    /// 画面録画かどうか
    var isScreenRecording: Bool {
        if case .screenRecording = self { return true }
        return false
    }
}

// MARK: - AudioSourceProvider

/// 利用可能な音源リソースを取得するヘルパー
enum AudioSourceProvider {
    /// システム音声・マイク・アプリケーション一覧を取得する
    static func availableSources() async -> [AudioSourceType] {
        var sources: [AudioSourceType] = []

        // 1. 画面録画（動画＋音声）
        sources.append(.screenRecording)

        // 2. システム全体（デフォルト）
        sources.append(.systemAudio)

        // 3. マイクデバイス
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        for device in discoverySession.devices {
            sources.append(.microphone(deviceID: device.uniqueID, name: device.localizedName))
        }

        // 4. 画面録画（動画＋音声）は既に追加済み

        // 5. ScreenCaptureKit からアプリケーション一覧を取得
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            var seen = Set<String>()
            for app in content.applications {
                let bundleID = app.bundleIdentifier
                guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)
                let name = app.applicationName.isEmpty ? bundleID : app.applicationName
                sources.append(.application(bundleID: bundleID, name: name))
            }
        } catch {
            // 権限エラー等の場合はマイクとシステム全体のみ
        }

        return sources
    }
}
