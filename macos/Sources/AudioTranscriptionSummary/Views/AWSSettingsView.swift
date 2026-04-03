// AWSSettingsView.swift
// アプリ設定画面（AWS 認証情報・録音データ保存先）
// Form レイアウトで認証情報の入力フィールドと操作ボタンを提供する

import SwiftUI

// MARK: - AWS リージョン一覧

/// Amazon Transcribe が利用可能な主要リージョン
private let awsRegions: [(id: String, name: String)] = [
    ("ap-northeast-1", "アジアパシフィック（東京）"),
    ("ap-northeast-3", "アジアパシフィック（大阪）"),
    ("ap-southeast-1", "アジアパシフィック（シンガポール）"),
    ("ap-southeast-2", "アジアパシフィック（シドニー）"),
    ("us-east-1", "米国東部（バージニア北部）"),
    ("us-east-2", "米国東部（オハイオ）"),
    ("us-west-2", "米国西部（オレゴン）"),
    ("eu-west-1", "欧州（アイルランド）"),
    ("eu-west-2", "欧州（ロンドン）"),
    ("eu-central-1", "欧州（フランクフルト）"),
    ("ca-central-1", "カナダ（中部）"),
    ("sa-east-1", "南米（サンパウロ）"),
]

// MARK: - AWSSettingsView（AWS 設定画面）

/// AWS 認証情報の設定画面
/// Access Key ID、Secret Access Key、リージョン、S3 バケット名の入力と
/// 保存・削除・接続テスト操作を提供する
struct AWSSettingsView: View {
    /// AWS 設定画面の ViewModel
    @ObservedObject var viewModel: AWSSettingsViewModel

    /// シートを閉じるための Environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // タイトル
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.accentColor)
                Text("アプリ設定")
                    .font(.headline)
                Spacer()
                // 接続ステータスインジケーター
                connectionStatusBadge

                Button("閉じる") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                // MARK: 録音データ保存先セクション
                Section {
                    LabeledContent("保存先フォルダ") {
                        HStack(spacing: 8) {
                            if viewModel.recordingDirectoryPath.isEmpty {
                                Text("システム一時フォルダ（デフォルト）")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 250, alignment: .leading)
                            } else {
                                Text(viewModel.recordingDirectoryPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 250, alignment: .leading)
                                    .help(viewModel.recordingDirectoryPath)
                            }

                            Button("選択...") {
                                viewModel.chooseRecordingDirectory()
                            }
                            .buttonStyle(.bordered)

                            if !viewModel.recordingDirectoryPath.isEmpty {
                                Button {
                                    viewModel.resetRecordingDirectory()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("デフォルトに戻す")
                            }
                        }
                    }
                } header: {
                    Label("録音データ保存先", systemImage: "folder.fill")
                } footer: {
                    Text("システム音声キャプチャ・画面録画のデータが保存されるフォルダを指定します。未設定の場合はシステム一時フォルダに保存されます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: エクスポートデータ保存先セクション
                Section {
                    LabeledContent("保存先フォルダ") {
                        HStack(spacing: 8) {
                            if viewModel.exportDirectoryPath.isEmpty {
                                Text("毎回ダイアログで選択")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 250, alignment: .leading)
                            } else {
                                Text(viewModel.exportDirectoryPath)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 250, alignment: .leading)
                                    .help(viewModel.exportDirectoryPath)
                            }

                            Button("選択...") {
                                viewModel.chooseExportDirectory()
                            }
                            .buttonStyle(.bordered)

                            if !viewModel.exportDirectoryPath.isEmpty {
                                Button {
                                    viewModel.resetExportDirectory()
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("デフォルトに戻す")
                            }
                        }
                    }
                } header: {
                    Label("エクスポート保存先", systemImage: "square.and.arrow.up")
                } footer: {
                    Text("文字起こし結果・要約のエクスポート先フォルダを指定します。未設定の場合はエクスポート時に毎回保存先を選択します。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: 認証情報入力セクション
                Section {
                    LabeledContent("Access Key ID") {
                        TextField("AKIA...", text: $viewModel.accessKeyId)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }

                    LabeledContent("Secret Access Key") {
                        SecureField("wJalr...", text: $viewModel.secretAccessKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                } header: {
                    Label("認証情報", systemImage: "key.fill")
                }

                // MARK: リージョン・バケット設定セクション
                Section {
                    LabeledContent("リージョン") {
                        Picker("", selection: $viewModel.region) {
                            ForEach(awsRegions, id: \.id) { region in
                                Text("\(region.name) (\(region.id))")
                                    .tag(region.id)
                            }
                        }
                        .frame(maxWidth: 300)
                    }

                    LabeledContent("S3 バケット名") {
                        TextField("my-transcription-bucket", text: $viewModel.s3BucketName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                } header: {
                    Label("S3 設定", systemImage: "externaldrive.fill")
                }

                // MARK: フィードバック表示
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }

                if viewModel.isSaved && viewModel.errorMessage == nil && !viewModel.isTesting {
                    Section {
                        Label("認証情報は保存済みです", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }

                if let testResult = viewModel.connectionTestResult {
                    Section {
                        Label(testResult, systemImage: viewModel.connectionTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(viewModel.connectionTestSuccess ? .green : .red)
                    }
                }

                // MARK: 操作ボタン
                Section {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.saveCredentials()
                        } label: {
                            Label("保存", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task {
                                await viewModel.testConnection()
                            }
                        } label: {
                            if viewModel.isTesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("テスト中...")
                            } else {
                                Label("接続テスト", systemImage: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isSaved || viewModel.isTesting)

                        Spacer()

                        Button(role: .destructive) {
                            viewModel.deleteCredentials()
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isSaved)
                    }
                }

                // MARK: リアルタイム文字起こし・翻訳設定セクション
                Section("リアルタイム文字起こし・翻訳") {
                    Toggle("リアルタイム文字起こしを有効にする", isOn: $viewModel.isRealtimeEnabled)
                    Toggle("言語自動判別を有効にする", isOn: $viewModel.isAutoDetectEnabled)
                        .disabled(!viewModel.isRealtimeEnabled)
                    LabeledContent("デフォルト翻訳先言語") {
                        Picker("", selection: $viewModel.defaultTargetLanguage) {
                            ForEach(TranslationLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .frame(width: 150)
                    }
                    .disabled(!viewModel.isRealtimeEnabled)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(minWidth: 550, minHeight: 650)
    }

    // MARK: - 接続ステータスバッジ

    /// 保存状態と接続テスト結果に応じたステータスバッジ
    @ViewBuilder
    private var connectionStatusBadge: some View {
        if viewModel.isTesting {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("テスト中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if viewModel.connectionTestSuccess {
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("接続済み")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        } else if viewModel.isSaved {
            HStack(spacing: 4) {
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                Text("未検証")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            HStack(spacing: 4) {
                Circle()
                    .fill(.gray)
                    .frame(width: 8, height: 8)
                Text("未設定")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
