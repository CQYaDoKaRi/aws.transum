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
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(viewModel.accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.clear, lineWidth: 1)
                                    )
                            }
                            settingsRow("Secret Access Key") {
                                SecureField("Secret Access Key を入力", text: $viewModel.secretAccessKey)
                                    .textFieldStyle(.squareBorder)
                                    .focusable()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(viewModel.secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.clear, lineWidth: 1)
                                    )
                            }
                        }

                        // AWS Profile 方式: プロファイル Picker + リフレッシュボタンを表示
                        if viewModel.authMethod == .awsProfile {
                            settingsRow("プロファイル") {
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
                                }
                            }

                            // プロファイル読み込みエラー表示
                            if let error = viewModel.profileLoadError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }

                        // IAM Identity Center（SSO）方式
                        if viewModel.authMethod == .sso {
                            settingsRow("Start URL") {
                                TextField("https://my-org.awsapps.com/start", text: $viewModel.ssoStartUrl)
                                    .textFieldStyle(.squareBorder)
                                    .focusable()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(viewModel.ssoStartUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.clear, lineWidth: 1)
                                    )
                            }
                            settingsRow("SSO リージョン") {
                                Picker("", selection: $viewModel.ssoRegion) {
                                    Text("選択してください").tag("")
                                    ForEach(awsRegions, id: \.id) { r in
                                        Text("\(r.name) (\(r.id))").tag(r.id)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(viewModel.ssoRegion.isEmpty ? Color.red : Color.clear, lineWidth: 1)
                                )
                            }

                            // SSO ログインボタン（SSOリージョンと同じ幅）
                            settingsRow("") {
                                ssoLoginButton
                            }

                            // User Code 表示（ブラウザ認証待ち時）+ コピーボタン
                            if case .waitingForBrowser(let userCode, _) = viewModel.ssoAuthService.loginState {
                                settingsRow("User Code") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(userCode)
                                                .font(.system(.title2, design: .monospaced))
                                                .fontWeight(.bold)
                                                .foregroundColor(.accentColor)
                                                .textSelection(.enabled)
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(userCode, forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("コードをコピー")
                                        }
                                        Text("ブラウザで上記コードを入力してください")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // ポーリング中のプログレスインジケーター（waitingForBrowser 状態で表示）
                            if case .waitingForBrowser = viewModel.ssoAuthService.loginState {
                                settingsRow("") {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("ブラウザでの認証を待機中...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // アカウント Picker（認証成功後）
                            if !viewModel.ssoAuthService.accounts.isEmpty {
                                settingsRow("アカウント") {
                                    Picker("", selection: $viewModel.ssoAccountId) {
                                        Text("選択してください").tag("")
                                        ForEach(viewModel.ssoAuthService.accounts) { account in
                                            Text(account.displayName).tag(account.accountId)
                                        }
                                    }
                                    .labelsHidden()
                                    .onChange(of: viewModel.ssoAccountId) { _, newValue in
                                        guard !newValue.isEmpty else { return }
                                        Task {
                                            try? await viewModel.ssoAuthService.fetchRoles(accountId: newValue)
                                        }
                                    }
                                }
                            }

                            // ロール Picker（アカウント選択後）
                            if !viewModel.ssoAuthService.roles.isEmpty {
                                settingsRow("ロール") {
                                    Picker("", selection: $viewModel.ssoRoleName) {
                                        Text("選択してください").tag("")
                                        ForEach(viewModel.ssoAuthService.roles, id: \.self) { role in
                                            Text(role).tag(role)
                                        }
                                    }
                                    .labelsHidden()
                                    .onChange(of: viewModel.ssoRoleName) { _, newValue in
                                        guard !newValue.isEmpty, !viewModel.ssoAccountId.isEmpty else { return }
                                        Task {
                                            try? await viewModel.ssoAuthService.fetchCredentials(
                                                accountId: viewModel.ssoAccountId,
                                                roleName: newValue
                                            )
                                            viewModel.updateSSOSavedState()
                                        }
                                    }
                                }
                            }

                        }
                    }

                    // AWS 環境設定
                    settingsGroup(title: "AWS 環境設定", icon: "cloud.fill") {
                        settingsRow("リージョン") {
                            Picker("", selection: $viewModel.region) {
                                ForEach(awsRegions, id: \.id) { r in
                                    Text("\(r.name) (\(r.id))").tag(r.id)
                                }
                            }
                            .onChange(of: viewModel.region) { _, _ in
                                // リージョン変更時にバケット一覧をクリア
                                viewModel.availableBuckets = []
                                viewModel.bucketSearchText = ""
                            }
                        }
                        settingsRow("S3 バケット") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    // 検索フィルター付きテキストフィールド
                                    TextField("バケット名を検索 / 入力", text: $viewModel.bucketSearchText)
                                        .textFieldStyle(.squareBorder)
                                        .focusable()
                                        .onChange(of: viewModel.bucketSearchText) { _, newValue in
                                            if viewModel.availableBuckets.isEmpty || !viewModel.availableBuckets.contains(newValue) {
                                                viewModel.s3BucketName = newValue
                                            }
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(viewModel.s3BucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.red : Color.clear, lineWidth: 1)
                                        )
                                    // バケット一覧取得ボタン
                                    Button {
                                        Task { await viewModel.fetchBuckets() }
                                    } label: {
                                        if viewModel.isLoadingBuckets {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(viewModel.isLoadingBuckets)
                                    .help("S3 バケット一覧を取得")
                                }
                                // バケット選択リスト（取得済みの場合）
                                if !viewModel.availableBuckets.isEmpty {
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 0) {
                                            ForEach(viewModel.filteredBuckets, id: \.self) { bucket in
                                                bucketRow(bucket)
                                                Divider()
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 120)
                                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color(.separatorColor), lineWidth: 1))
                                    
                                    Text("\(viewModel.filteredBuckets.count) / \(viewModel.availableBuckets.count) バケット")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                // エラー表示
                                if let err = viewModel.bucketLoadError {
                                    Text(err).font(.caption2).foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    // 操作ボタン
                    HStack(spacing: 12) {
                        Button {
                            viewModel.saveCredentials()
                        } label: {
                            if viewModel.isTesting {
                                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("保存＋接続テスト中...") }
                            } else {
                                Label("保存", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isTesting)
                        Spacer()
                        Button(role: .destructive) { viewModel.deleteCredentials() } label: { Label("削除", systemImage: "trash") }
                            .buttonStyle(.bordered).disabled(!viewModel.isSaved)
                    }
                }
                .padding()
            }

            // ステータスバー（下部固定: 左寄せ統一）
            Divider()
            HStack(spacing: 4) {
                if viewModel.isTesting {
                    ProgressView().controlSize(.small)
                    Text("接続テスト中...").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.connectionTestSuccess {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    if viewModel.authMethod == .sso, let mins = viewModel.ssoRemainingMinutes {
                        Text("接続済み（残り \(mins) 分）").font(.caption).foregroundStyle(.green)
                    } else {
                        Text("接続済み").font(.caption).foregroundStyle(.green)
                    }
                } else if viewModel.authMethod == .sso, viewModel.ssoAuthService.loginState == .authenticated,
                          let mins = viewModel.ssoRemainingMinutes {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("SSO 認証済み（残り \(mins) 分）").font(.caption).foregroundStyle(.green)
                } else if let err = viewModel.errorMessage {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if let result = viewModel.connectionTestResult, !viewModel.connectionTestSuccess {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(result).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if viewModel.authMethod == .sso, case .error(let msg) = viewModel.ssoAuthService.loginState {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if !viewModel.isSaved {
                    Circle().fill(.gray).frame(width: 8, height: 8)
                    Text("未設定").font(.caption).foregroundStyle(.secondary)
                } else {
                    Circle().fill(.yellow).frame(width: 8, height: 8)
                    Text("未検証").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.controlBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 550, minHeight: 500)
        .onAppear {
            // 設定ファイルを再読み込みして復元
            viewModel.loadAll()

            // sheet 内の TextField にフォーカスが当たるようにキーウィンドウを設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeKey()
            }
            // バケット名が設定済みなら検索テキストに反映
            if !viewModel.s3BucketName.isEmpty {
                viewModel.bucketSearchText = viewModel.s3BucketName
            }
            // SSO認証済みでアカウント選択済みの場合、ロール一覧を自動取得
            if viewModel.authMethod == .sso,
               viewModel.ssoAuthService.loginState == .authenticated || !viewModel.ssoAuthService.accounts.isEmpty {
                if !viewModel.ssoAccountId.isEmpty && viewModel.ssoAuthService.roles.isEmpty {
                    Task {
                        if viewModel.ssoAuthService.accounts.isEmpty {
                            try? await viewModel.ssoAuthService.fetchAccounts()
                        }
                        if !viewModel.ssoAccountId.isEmpty {
                            try? await viewModel.ssoAuthService.fetchRoles(accountId: viewModel.ssoAccountId)
                        }
                    }
                }
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

    // MARK: - S3 バケット行

    private func bucketRow(_ bucket: String) -> some View {
        let isSelected = viewModel.s3BucketName == bucket
        return Button {
            viewModel.s3BucketName = bucket
            viewModel.bucketSearchText = bucket
        } label: {
            HStack {
                Text(bucket).font(.caption).lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2).foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - SSO ステータスラベル

    // MARK: - SSO ログインボタン

    /// SSO ログインボタン（状態に応じて無効化）
    private var ssoLoginButton: some View {
        let isLoggingIn: Bool = {
            switch viewModel.ssoAuthService.loginState {
            case .registering, .waitingForBrowser, .polling:
                return true
            default:
                return false
            }
        }()

        return Button {
            Task {
                // SSO 再接続時にアカウント・ロールをリセット
                viewModel.ssoAccountId = ""
                viewModel.ssoRoleName = ""

                try? await viewModel.ssoAuthService.startLogin(
                    startUrl: viewModel.ssoStartUrl.trimmingCharacters(in: .whitespacesAndNewlines),
                    region: viewModel.ssoRegion
                )
                // 認証成功後にアカウント一覧を取得
                if viewModel.ssoAuthService.loginState == .selectingAccount {
                    try? await viewModel.ssoAuthService.fetchAccounts()
                }
            }
        } label: {
            if isLoggingIn {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("SSO ログイン中...")
                }
                .frame(maxWidth: .infinity)
            } else {
                Label("SSO ログイン", systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            viewModel.ssoStartUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.ssoRegion.isEmpty
            || isLoggingIn
        )
    }

}
