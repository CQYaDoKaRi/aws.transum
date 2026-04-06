// AudioTranscriptionSummaryApp.swift
// アプリケーションのエントリポイント
// 起動時に JSON 設定ファイルから AWS 認証情報を読み込み、
// 設定済みなら TranscribeClient を AppViewModel に注入する

import SwiftUI

/// macOS 音声文字起こし・要約アプリケーションのメインエントリポイント
@main
struct AudioTranscriptionSummaryApp: App {

    /// アプリ設定画面の ViewModel
    @StateObject private var awsSettingsViewModel: AWSSettingsViewModel

    /// アプリケーション全体の状態を管理する ViewModel
    @StateObject private var appViewModel: AppViewModel

    init() {
        // Dock にアプリアイコンを表示する
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.applicationIconImage = Self.generateAppIcon()

        let settingsVM = AWSSettingsViewModel()
        _awsSettingsViewModel = StateObject(wrappedValue: settingsVM)

        // JSON から認証情報を読み込み、TranscribeClient を構築
        let vm = Self.createAppViewModel()
        _appViewModel = StateObject(wrappedValue: vm)
    }

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: appViewModel, awsSettingsViewModel: awsSettingsViewModel)
        }
    }

    /// アプリアイコンを生成する（波形＋ドキュメント＋要約のデザイン）
    private static func generateAppIcon() -> NSImage {
        let size: CGFloat = 512
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        // 角丸背景（macOS アイコンスタイル）
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let cornerRadius: CGFloat = size * 0.22
        let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // グラデーション背景（深い青 → 明るい青）
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.10, green: 0.30, blue: 0.75, alpha: 1.0),
            CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1.0)
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: size / 2, y: 0), end: CGPoint(x: size / 2, y: size), options: [])
        }
        ctx.restoreGState()

        // 波形（音声を表現）— 中央上部に白い波形バー
        ctx.saveGState()
        let waveColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.95)
        ctx.setFillColor(waveColor)
        let barWidth: CGFloat = 18
        let barSpacing: CGFloat = 12
        let barHeights: [CGFloat] = [60, 100, 140, 180, 160, 200, 150, 120, 170, 130, 90, 60]
        let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barSpacing
        let startX = (size - totalWidth) / 2
        let centerY: CGFloat = size * 0.58

        for (i, h) in barHeights.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let barRect = CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
            let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            ctx.addPath(barPath)
            ctx.fillPath()
        }
        ctx.restoreGState()

        // ドキュメントアイコン（右下に小さく）— 文字起こし・要約を表現
        ctx.saveGState()
        let docX: CGFloat = size * 0.62
        let docY: CGFloat = size * 0.06
        let docW: CGFloat = size * 0.28
        let docH: CGFloat = size * 0.32
        let docRect = CGRect(x: docX, y: docY, width: docW, height: docH)
        let docPath = CGPath(roundedRect: docRect, cornerWidth: 8, cornerHeight: 8, transform: nil)

        // ドキュメント背景（半透明白）
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.addPath(docPath)
        ctx.fillPath()

        // ドキュメント内のテキスト行（青い線）
        let lineColor = CGColor(red: 0.15, green: 0.40, blue: 0.85, alpha: 0.7)
        ctx.setFillColor(lineColor)
        let lineH: CGFloat = 6
        let lineMargin: CGFloat = 16
        let lineWidths: [CGFloat] = [0.8, 0.65, 0.75, 0.5]
        for (i, widthRatio) in lineWidths.enumerated() {
            let ly = docY + docH - lineMargin - CGFloat(i) * (lineH + 10) - lineH
            let lw = (docW - lineMargin * 2) * widthRatio
            let lineRect = CGRect(x: docX + lineMargin, y: ly, width: lw, height: lineH)
            ctx.fill(lineRect)
        }
        ctx.restoreGState()

        // 「T」文字（左下に）— Transcription を表現
        ctx.saveGState()
        let tFont = NSFont.systemFont(ofSize: size * 0.18, weight: .bold)
        let tStr = NSAttributedString(string: "T", attributes: [
            .font: tFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
        ])
        let tSize = tStr.size()
        let tPoint = NSPoint(x: size * 0.10, y: size * 0.08)
        tStr.draw(at: tPoint)
        ctx.restoreGState()

        image.unlockFocus()
        return image
    }

    /// AWS 認証情報から AppViewModel を構築する
    /// 認証情報が未設定またはサービス初期化に失敗した場合はデフォルト（SFSpeechRecognizer）にフォールバック
    private static func createAppViewModel() -> AppViewModel {
        guard let credentials = AWSSettingsViewModel.loadAWSCredentials() else {
            return AppViewModel()
        }

        let bucketName = AWSSettingsViewModel.loadS3BucketName()
        guard !bucketName.isEmpty else {
            return AppViewModel()
        }

        // AWS SDK の初期化を試みる
        // 失敗した場合でも TranscribeClient を構築し、transcribe 呼び出し時にエラーを返す
        let jsonCredManager = JSONCredentialManager()

        do {
            let s3Service = try AWSS3Service(credentials: credentials)
            let transcribeService = try AWSTranscribeService(credentials: credentials)
            let transcribeClient = TranscribeClient(
                credentialManager: jsonCredManager,
                s3BucketName: bucketName,
                s3Client: s3Service,
                transcribeClient: transcribeService
            )
            return AppViewModel(transcriber: transcribeClient)
        } catch {
            // SDK 初期化失敗時もフォールバックせず、エラーを保持する ViewModel を返す
            // ユーザーが文字起こしを試みた際にエラーメッセージが表示される
            return AppViewModel()
        }
    }
}

// MARK: - JSONCredentialManager

/// JSON 設定ファイルから認証情報を読み込む AWSCredentialManaging 実装
final class JSONCredentialManager: AWSCredentialManaging, Sendable {
    private let store = AppSettingsStore()

    func loadCredentials() -> AWSCredentials? {
        let s = store.load()
        let c = AWSCredentials(accessKeyId: s.accessKeyId, secretAccessKey: s.secretAccessKey, region: s.region)
        return c.isValid ? c : nil
    }

    func saveCredentials(_ credentials: AWSCredentials) throws {
        var s = store.load()
        s.accessKeyId = credentials.accessKeyId
        s.secretAccessKey = credentials.secretAccessKey
        s.region = credentials.region
        try store.save(s)
    }

    func deleteCredentials() throws {
        var s = store.load()
        s.accessKeyId = ""
        s.secretAccessKey = ""
        try store.save(s)
    }

    var hasCredentials: Bool {
        loadCredentials() != nil
    }
}
