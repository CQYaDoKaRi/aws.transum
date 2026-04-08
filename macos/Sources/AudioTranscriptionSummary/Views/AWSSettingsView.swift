// AWSSettingsView.swift
// アプリ設定画面（テキスト入力可能な VStack ベースレイアウト）

import SwiftUI

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

struct AWSSettingsView: View {
    @ObservedObject var viewModel: AWSSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // タイトルバー
            HStack {
                Image(systemName: "gearshape.fill").foregroundColor(.accentColor)
                Text("アプリ設定").font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }.buttonStyle(.bordered).keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            // 設定内容
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // 録音データ保存先
                    settingsGroup(title: "録音データ保存先", icon: "folder.fill") {
                        settingsRow("保存先フォルダ") {
                            HStack(spacing: 8) {
                                Text(viewModel.recordingDirectoryPath.isEmpty ? "システム一時フォルダ（デフォルト）" : viewModel.recordingDirectoryPath)
                                    .foregroundColor(viewModel.recordingDirectoryPath.isEmpty ? .secondary : .primary)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("選択...") { viewModel.chooseRecordingDirectory() }.controlSize(.small)
                                if !viewModel.recordingDirectoryPath.isEmpty {
                                    Button { viewModel.resetRecordingDirectory() } label: { Image(systemName: "arrow.counterclockwise") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    // エクスポート保存先
                    settingsGroup(title: "エクスポート保存先", icon: "square.and.arrow.up") {
                        settingsRow("保存先フォルダ") {
                            HStack(spacing: 8) {
                                Text(viewModel.exportDirectoryPath.isEmpty ? "毎回ダイアログで選択" : viewModel.exportDirectoryPath)
                                    .foregroundColor(viewModel.exportDirectoryPath.isEmpty ? .secondary : .primary)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("選択...") { viewModel.chooseExportDirectory() }.controlSize(.small)
                                if !viewModel.exportDirectoryPath.isEmpty {
                                    Button { viewModel.resetExportDirectory() } label: { Image(systemName: "arrow.counterclockwise") }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                    }

                    // 認証情報
                    settingsGroup(title: "認証情報", icon: "key.fill") {
                        // 認証方式の切り替え（セグメントコントロール）
                        settingsRow("認証方式") {
                            Picker("", selection: $viewModel.authMethod) {
                                ForEach(AuthMethod.allCases) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Access Key 方式: Access Key ID / Secret Access Key フィールドを表示
                        if viewModel.authMethod == .accessKey {
                            settingsRow("Access Key ID") {
                                TextField("Access Key ID を入力", text: $viewModel.accessKeyId)
                                    .textFieldStyle(.squareBorder)
                                    .focusable()
                            }
                            settingsRow("Secret Access Key") {
                                SecureField("Secret Access Key を入力", text: $viewModel.secretAccessKey)
                                    .textFieldStyle(.squareBorder)
                                    .focusable()
                            }
                        }

                        // AWS Profile 方式: プロファイル Picker + リフレッシュボタンを表示
                        if viewModel.authMethod == .awsProfile {
                            settingsRow("プロファイル") {
                                HStack(spacing: 8) {
                                    if viewModel.availableProfiles.isEmpty {
                                        Text("プロファイルなし")
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else {
                                        Picker("", selection: $viewModel.selectedProfileName) {
                                            ForEach(viewModel.availableProfiles, id: \.self) { profile in
                                                Text(profile).tag(profile)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    Button {
                                        viewModel.refreshProfiles()
                                    } label: {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("プロファイル一覧を再読み込み")
                                }
                            }

                            // プロファイル読み込みエラー表示
                            if let error = viewModel.profileLoadError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                    }

                    // S3 設定
                    settingsGroup(title: "S3 設定", icon: "externaldrive.fill") {
                        settingsRow("リージョン") {
                            Picker("", selection: $viewModel.region) {
                                ForEach(awsRegions, id: \.id) { r in
                                    Text("\(r.name) (\(r.id))").tag(r.id)
                                }
                            }
                        }
                        settingsRow("S3 バケット名") {
                            TextField("バケット名を入力", text: $viewModel.s3BucketName)
                                .textFieldStyle(.squareBorder)
                                .focusable()
                        }
                    }

                    // エラーメッセージ（バリデーション用）
                    if let err = viewModel.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red).font(.caption)
                    }

                    // 操作ボタン
                    HStack(spacing: 12) {
                        Button { viewModel.saveCredentials() } label: { Label("保存", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent)
                        Button { Task { await viewModel.testConnection() } } label: {
                            if viewModel.isTesting { ProgressView().controlSize(.small); Text("テスト中...") }
                            else { Label("接続テスト", systemImage: "antenna.radiowaves.left.and.right") }
                        }
                        .buttonStyle(.bordered).disabled(!viewModel.isSaved || viewModel.isTesting)
                        Spacer()
                        Button(role: .destructive) { viewModel.deleteCredentials() } label: { Label("削除", systemImage: "trash") }
                            .buttonStyle(.bordered).disabled(!viewModel.isSaved)
                    }
                }
                .padding()
            }

            // ステータスバー（下部固定）
            Divider()
            HStack(spacing: 8) {
                if viewModel.isTesting {
                    ProgressView().controlSize(.small)
                    Text("接続テスト中...").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.connectionTestSuccess {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("AWS 接続済み").font(.caption).foregroundStyle(.green)
                } else if let result = viewModel.connectionTestResult {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(result).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if viewModel.isSaved {
                    Circle().fill(.yellow).frame(width: 8, height: 8)
                    Text("未検証 — 接続テストを実行してください").font(.caption).foregroundStyle(.secondary)
                } else {
                    Circle().fill(.gray).frame(width: 8, height: 8)
                    Text("AWS 未設定").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 550, minHeight: 500)
        .onAppear {
            // sheet 内の TextField にフォーカスが当たるようにキーウィンドウを設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeKey()
            }
        }
    }

    // MARK: - 設定グループ

    private func settingsGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.controlBackgroundColor)))
        }
    }

    // MARK: - 設定行（ラベル + コンテンツ 右寄せ）

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            content()
        }
    }

}
