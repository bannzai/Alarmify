import SwiftUI

/// 設定画面。アカウント ID の確認と、アプリ内からのアカウント削除 (App Store Review Guideline 5.1.1 (v)) を行う
struct SettingsView: View {
    /// 削除フローの進行状態
    private enum DeletionState: Equatable {
        case idle
        case deleting
        case deleted
        case failed(message: String)
    }

    /// 公開している削除手順のページ (英語版)。ロケール別の URL が壊れた時の戻り先
    private static let englishAccountDeletionGuideURL = URL(string: "https://bannzai.github.io/Alarmify/AccountDeletion-en")!

    var deletionService: AccountDeletionService = RemoteAccountDeletionService()

    @State private var credential = AccountStore.load()
    @State private var deletionState: DeletionState = .idle
    /// 削除の確認ダイアログの表示状態
    @State private var deletionConfirmation = false

    var body: some View {
        List {
            Section {
                if let credential {
                    LabeledContent {
                        Text(credential.userId)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } label: {
                        // ja: アカウント ID
                        Text("Account ID")
                    }
                } else {
                    // ja: アカウントはまだ作成されていません
                    Text("No account has been created yet")
                        .foregroundStyle(.secondary)
                }
            } header: {
                // ja: アカウント
                Text("Account")
            } footer: {
                // ja: メールで削除を依頼する時は、このアカウント ID を書き添えてください
                Text("Include this account ID when you request deletion by email.")
            }

            Section {
                Button(role: .destructive) {
                    deletionConfirmation = true
                } label: {
                    HStack {
                        // ja: アカウントを削除
                        Text("Delete Account")
                        if deletionState == .deleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .accessibilityIdentifier("settings_delete_account")
                .disabled(credential == nil || deletionState == .deleting)

                Link(destination: accountDeletionGuideURL) {
                    // ja: 削除の手順と削除されるデータ
                    Text("Deletion steps and the data that is deleted")
                }
            } footer: {
                // ja: 削除すると、サーバー上の API トークン・端末情報・アラーム履歴がすべて消え、取り消せません。
                //
                // この iPhone に登録済みの AlarmKit のアラームは解除されません。アラーム一覧から個別に取り消してください
                Text("""
                    Deleting your account permanently removes your API tokens, device information, and alarm history from the server. This cannot be undone.

                    Alarms already scheduled on this iPhone are not cancelled. Cancel them individually from the alarm list.
                    """)
            }

            if case .failed(let message) = deletionState {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                } header: {
                    // ja: エラー
                    Text("Error")
                }
            }

#if DEBUG
            DeveloperMenuSection(credential: $credential)
#endif
        }
        // ja: 設定
        .navigationTitle("Settings")
        .confirmationDialog(
            // ja: アカウントを削除しますか?
            Text("Delete your account?"),
            isPresented: $deletionConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await deleteAccount() }
            } label: {
                // ja: 削除する
                Text("Delete")
            }
            Button(role: .cancel) {
            } label: {
                // ja: キャンセル
                Text("Cancel")
            }
        } message: {
            // ja: サーバー上のデータがすべて削除され、取り消せません
            Text("All of your data on the server will be deleted. This cannot be undone.")
        }
        .alert(
            // ja: アカウントを削除しました
            Text("Your account has been deleted"),
            isPresented: .init(
                get: { deletionState == .deleted },
                set: { presented in
                    if !presented {
                        deletionState = .idle
                    }
                }
            )
        ) {
            Button {
                deletionState = .idle
            } label: {
                // ja: OK
                Text("OK")
            }
        } message: {
            // ja: この iPhone に登録済みのアラームは残っています。不要な場合はアラーム一覧から取り消してください
            Text("Alarms already scheduled on this iPhone remain. Cancel them from the alarm list if you no longer need them.")
        }
    }

    /// 表示中の言語に対応する削除手順のページ
    private var accountDeletionGuideURL: URL {
        // ja: https://bannzai.github.io/Alarmify/AccountDeletion-ja
        URL(string: String(localized: "https://bannzai.github.io/Alarmify/AccountDeletion-en")) ?? Self.englishAccountDeletionGuideURL
    }

    private func deleteAccount() async {
        guard let credential else { return }
        deletionState = .deleting
        do {
            try await deletionService.deleteAccount(credential: credential)
            // 削除後はアプリを初期状態に戻し、匿名認証をやり直せるようにする
            AccountStore.clear()
            DeviceTokenStore.clear()
            self.credential = nil
            deletionState = .deleted
        } catch {
            deletionState = .failed(message: error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
