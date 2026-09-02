import SwiftUI

/// 設定画面。現在のプランの表示とペイウォールへの導線、アカウント ID の確認、法務ドキュメントへのリンク、
/// アプリ内からのアカウント削除 (App Store Review Guideline 5.1.1 (v)) を行う。
/// 見た目は仮 UI で、受領デザインの反映は #6 で行う
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

    @State private var session = AccountSession.shared
    @State private var deletionState: DeletionState = .idle

    /// entitlement 判定のキャッシュ (ProEntitlement.cacheEntitlement が更新する)。
    /// 購入・復元の直後に表示を追従させるため @AppStorage で購読する
    @AppStorage(.proEntitlementActive) private var proEntitlementActive = false
    /// entitlement の失効日時 (請求猶予期間があればその終了日時、epoch 秒)。買い切り・未購入では保存されないため Optional
    @AppStorage(.proEntitlementExpiration) private var proEntitlementExpiration: Double?
    /// 表示中のペイウォールの文脈。nil の間はペイウォールを出さない
    @State private var paywallTrigger: PaywallTrigger?
    /// プラン表示の判定に使う現在時刻。
    /// @AppStorage の値は時計が失効日時を越えても変わらないため、画面を開いたまま失効した時に
    /// body を再評価させる状態としてここに持つ (PR #20 レビュー指摘)
    @State private var now = Date.now
    /// バックグラウンドから戻った時に now を取り直すための scene の状態
    @Environment(\.scenePhase) private var scenePhase
    /// 削除の確認ダイアログの表示状態
    @State private var deletionConfirmation = false

    var body: some View {
        List {
            Section {
                LabeledContent {
                    if isPro {
                        Text("Pro")
                    } else {
                        // ja: 無料
                        Text("Free")
                    }
                } label: {
                    // ja: プラン
                    Text("Plan")
                }
                .accessibilityIdentifier("settings_plan")

                if !isPro {
                    Button {
                        paywallTrigger = .settings
                    } label: {
                        // ja: Pro にアップグレード
                        Text("Upgrade to Pro")
                    }
                    .accessibilityIdentifier("settings_upgrade_button")
                }
            } header: {
                // ja: 課金
                Text("Subscription")
            }

            Section {
                LabeledContent {
                    if let uid = session.uid {
                        Text(uid)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        // ja: サインイン中
                        Text("Signing in")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    // ja: アカウント ID
                    Text("Account ID")
                }
            } header: {
                // ja: アカウント
                Text("Account")
            } footer: {
                // ja: メールで削除を依頼する時は、このアカウント ID を書き添えてください
                Text("Include this account ID when you request deletion by email.")
            }

            Section {
                // ja: 利用規約
                Link(destination: LegalLinks.terms) { Text("Terms of Use") }
                // ja: プライバシーポリシー
                Link(destination: LegalLinks.privacyPolicy) { Text("Privacy Policy") }
                // ja: 特定商取引法に基づく表記
                Link(destination: LegalLinks.specifiedCommercialTransactionAct) { Text("Legal Notice") }
            } header: {
                // ja: 法務情報
                Text("Legal")
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
                .disabled(session.uid == nil || deletionState == .deleting)

                Link(destination: accountDeletionGuideURL) {
                    // ja: 削除の手順と削除されるデータ
                    Text("Deletion steps and the data that is deleted")
                }
            } footer: {
                // ja: 削除すると、サーバー上の API トークン・端末情報・アラーム履歴がすべて消え、取り消せません。
                //
                // この iPhone に登録済みのアラームは解除されません。アラーム一覧から個別に取り消してください
                Text("""
                    Deleting your account permanently removes your API tokens, device information, and alarm history from the server. This cannot be undone.

                    Alarms already scheduled on this iPhone are not cancelled. Cancel them individually from the alarm list.
                    """)
            }

            if case .failed(let message) = deletionState {
                Section {
                    Text(message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings_delete_error")
                } header: {
                    // ja: エラー
                    Text("Error")
                }
            }
        }
        // ja: 設定
        .navigationTitle("Settings")
        .sheet(item: $paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
        }
        .task(id: proEntitlementExpiration) {
            await refreshNowAtExpiration()
        }
        .onChange(of: scenePhase) { _, phase in
            // Task.sleep はアプリが停止している間は進まないため、前面に戻った時にも取り直す
            if phase == .active {
                now = .now
            }
        }
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
            .accessibilityIdentifier("settings_delete_confirm")
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

    /// キャッシュした entitlement が今この瞬間も有効か
    private var isPro: Bool {
        cachedProActive(
            active: proEntitlementActive,
            expirationDate: proEntitlementExpiration.map(Date.init(timeIntervalSince1970:)),
            now: now
        )
    }

    /// 失効日時まで待ってから now を取り直す。
    /// 失効日時が無い (買い切り・未購入) 場合と、すでに過ぎている場合は待たない。
    /// 何度呼んでも now が現在時刻になるだけで、同じ状態へ収束する (冪等)
    private func refreshNowAtExpiration() async {
        guard let expirationDate = proEntitlementExpiration.map(Date.init(timeIntervalSince1970:)) else { return }
        let interval = expirationDate.timeIntervalSince(.now)
        guard interval > 0 else {
            now = .now
            return
        }
        try? await Task.sleep(for: .seconds(interval))
        now = .now
    }

    private func deleteAccount() async {
        deletionState = .deleting
        do {
            try await session.deleteAccount()
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
