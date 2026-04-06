// swift-tools-version: 6.0
// Package.swift - AudioTranscriptionSummary アプリケーションのパッケージ定義

import PackageDescription

let package = Package(
    name: "AudioTranscriptionSummary",
    platforms: [
        // macOS 14（Sonoma）以降をデプロイメントターゲットに設定
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AudioTranscriptionSummary",
            targets: ["AudioTranscriptionSummary"]
        )
    ],
    dependencies: [
        // プロパティベーステスト用の SwiftCheck パッケージ
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0"),
        // AWS SDK for Swift（Amazon Transcribe / S3 連携用）
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0")
    ],
    targets: [
        // メインアプリケーションターゲット
        .executableTarget(
            name: "AudioTranscriptionSummary",
            dependencies: [
                .product(name: "AWSTranscribe", package: "aws-sdk-swift"),
                .product(name: "AWSTranscribeStreaming", package: "aws-sdk-swift"),
                .product(name: "AWSTranslate", package: "aws-sdk-swift"),
                .product(name: "AWSBedrockRuntime", package: "aws-sdk-swift"),
                .product(name: "AWSS3", package: "aws-sdk-swift")
            ],
            path: "Sources/AudioTranscriptionSummary"
        ),
        // テストターゲット（Swift Testing + SwiftCheck ベース、Xcode 環境で実行）
        .testTarget(
            name: "AudioTranscriptionSummaryTests",
            dependencies: [
                "AudioTranscriptionSummary",
                .product(name: "SwiftCheck", package: "SwiftCheck")
            ],
            path: "Tests/AudioTranscriptionSummaryTests"
        )
    ]
)
