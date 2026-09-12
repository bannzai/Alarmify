import AlarmKit
import LicenseList
import SwiftUI
import UserNotifications

/// 設定画面。プランとペイウォールへの導線、権限の状態、アカウント ID とサポート、法務ドキュメントへのリンク、
/// アプリ内からのアカウント削除 (App Store Review Guideline 5.1.1 (v)) を行う。構成と文言は design_handoff/screens/settings.md
struct SettingsView: View {
    /// 削除フローの進行状態
    private enum DeletionState: Equatable {
        case idle
        case deleting
        case deleted
        case failed(message: String)
    }

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
    /// バックグラウンドから戻った時に now と権限の状態を取り直すための scene の状態
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    /// 削除の確認ダイアログの表示状態
    @State private var deletionConfirmation = false
    @State private var alarmAuthorization = AlarmKitScheduler.authorizationState
    /// 通知の権限。取得前は nil (行の値を空にする)
    @State private var notificationAuthorization: UNAuthorizationStatus?
    /// 権限の要求に失敗した時のエラー
    @State private var permissionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ja: プラン
                SectionHeader(Text("Plan"), dense: true)
                planCard

                // ja: 権限
                SectionHeader(Text("Permissions"), dense: true)
                permissionsCard

                // ja: アカウント
                SectionHeader(Text("Account"), dense: true)
                accountCard

                // ja: 法務情報
                SectionHeader(Text("Legal"), dense: true)
                legalCard

                if DeveloperMenu.isAvailable {
                    NavigationLink {
                        DeveloperMenuView()
                    } label: {
                        // ja: 開発者メニュー
                        row(Text("Developer menu"), chevron: true)
                    }
                    .buttonStyle(.plain)
                    .card()
                    .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                    .padding(.top, 14)
                    .accessibilityIdentifier("debug_menu")
                }

                Button {
                    deletionConfirmation = true
                } label: {
                    HStack {
                        // ja: アカウントを削除
                        Text("Delete Account")
                            .font(.body)
                            .foregroundStyle(Color.destructive)
                        if deletionState == .deleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                    .rowPadding()
                }
                .buttonStyle(.plain)
                .card()
                .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
                .padding(.top, 14)
                .accessibilityIdentifier("settings_delete_account")
                .disabled(session.uid == nil || deletionState == .deleting)

                if case .failed(let message) = deletionState {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 12)
                        .accessibilityIdentifier("settings_delete_error")
                }
                if let permissionError {
                    Text(permissionError)
                        .font(.footnote)
                        .foregroundStyle(Color.destructive)
                        .padding(.horizontal, DesignMetrics.textHorizontalPadding)
                        .padding(.top, 12)
                        .accessibilityIdentifier("settings_permission_error")
                }
            }
            .padding(.bottom, 24)
        }
        .screenBackground()
        // ja: 設定
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
        }
        .task(id: proEntitlementExpiration) {
            await refreshNowAtExpiration()
        }
        .task { await refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            // Task.sleep はアプリが停止している間は進まないため、前面に戻った時にも取り直す。
            // OS の設定アプリで権限を変えて戻った時も同じタイミングで読み直す
            if phase == .active {
                now = .now
                Task { await refreshPermissions() }
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
            Button {
                openURL(LegalLinks.accountDeletionGuide)
            } label: {
                // ja: 削除の手順と削除されるデータを見る
                Text("See what gets deleted")
            }
            Button(role: .cancel) {
            } label: {
                // ja: キャンセル
                Text("Cancel")
            }
        } message: {
            // ja: サーバー上の API トークン・端末情報・アラーム履歴がすべて消え、取り消せません。この iPhone に登録済みのアラームは解除されません。
            Text("Your API tokens, device information, and alarm history are permanently removed from the server. This cannot be undone. Alarms already scheduled on this iPhone are not cancelled.")
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

    // MARK: - カード

    private var planCard: some View {
        VStack(spacing: 0) {
            HStack {
                // ja: プラン
                Text("Plan")
                    .font(.body)
                    .foregroundStyle(Color.paper)
                Spacer()
                planText
                    .font(.body)
                    .foregroundStyle(Color.paperTertiary)
            }
            .rowPadding()
            .accessibilityIdentifier("settings_plan")
            if !isPro {
                HairlineDivider()
                Button {
                    paywallTrigger = .settings
                } label: {
                    // 製品名 + Pro。翻訳しない
                    row(Text(verbatim: "Signalarm Pro"), chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_upgrade_button")
            }
        }
        .card()
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
    }

    /// プランの値。Pro は失効日時があれば併記する (買い切り・猶予期間なしでは日時が無い)
    private var planText: Text {
        guard isPro else {
            // ja: 無料
            return Text("Free")
        }
        if let expiration = proEntitlementExpiration.map(Date.init(timeIntervalSince1970:)) {
            // ja: Pro (%@ まで)
            return Text("Pro until \(expiration, format: .dateTime.month(.abbreviated).day())")
        }
        return Text(verbatim: "Pro")
    }

    private var permissionsCard: some View {
        VStack(spacing: 0) {
            Button {
                Task { await handleAlarmPermissionTap() }
            } label: {
                HStack {
                    // ja: アラーム
                    Text("Alarms")
                        .font(.body)
                        .foregroundStyle(Color.paper)
                    Spacer()
                    alarmAuthorizationText
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                }
                .rowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_permission_alarms")
            HairlineDivider()
            Button {
                Task { await handleNotificationPermissionTap() }
            } label: {
                HStack {
                    // ja: 通知
                    Text("Notifications")
                        .font(.body)
                        .foregroundStyle(Color.paper)
                    Spacer()
                    if let notificationAuthorization {
                        notificationAuthorizationText(notificationAuthorization)
                            .font(.body)
                            .foregroundStyle(Color.paperTertiary)
                    }
                }
                .rowPadding()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_permission_notifications")
        }
        .card()
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
    }

    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack {
                // ja: アカウント ID
                Text("Account ID")
                    .font(.body)
                    .foregroundStyle(Color.paper)
                Spacer()
                if let uid = session.uid {
                    Text(verbatim: uid)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.paperTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160, alignment: .trailing)
                        .textSelection(.enabled)
                } else {
                    // ja: サインイン中
                    Text("Signing in")
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                }
            }
            .rowPadding()
            .accessibilityIdentifier("settings_account_id")
            HairlineDivider()
            Link(destination: LegalLinks.supportMail(accountID: session.uid)) {
                HStack {
                    // ja: サポート
                    Text("Support")
                        .font(.body)
                        .foregroundStyle(Color.paper)
                    Spacer()
                    // ja: メール
                    Text("Email")
                        .font(.body)
                        .foregroundStyle(Color.paperTertiary)
                    RowChevron()
                }
                .rowPadding()
            }
            .accessibilityIdentifier("settings_support")
        }
        .card()
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
    }

    private var legalCard: some View {
        VStack(spacing: 0) {
            // ja: 利用規約
            Link(destination: LegalLinks.terms) { row(Text("Terms of Use"), chevron: true) }
            HairlineDivider()
            // ja: プライバシーポリシー
            Link(destination: LegalLinks.privacyPolicy) { row(Text("Privacy Policy"), chevron: true) }
            HairlineDivider()
            // ja: 特定商取引法に基づく表記
            Link(destination: LegalLinks.specifiedCommercialTransactionAct) { row(Text("Legal Notice"), chevron: true) }
            HairlineDivider()
            NavigationLink {
                LicenseListView()
                    .licenseViewStyle(.withRepositoryAnchorLink)
                    // ja: OSS ライセンス
                    .navigationTitle("Open Source Licenses")
            } label: {
                // ja: OSS ライセンス
                row(Text("Open Source Licenses"), chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_oss_licenses")
        }
        .card()
        .padding(.horizontal, DesignMetrics.screenHorizontalPadding)
    }

    /// 遷移する行 (ラベルとシェブロン)
    private func row(_ label: Text, chevron: Bool) -> some View {
        HStack {
            label
                .font(.body)
                .foregroundStyle(Color.paper)
            Spacer()
            if chevron {
                RowChevron()
            }
        }
        .rowPadding()
        .contentShape(Rectangle())
    }

    // MARK: - 権限

    private var alarmAuthorizationText: Text {
        switch alarmAuthorization {
        case .authorized:
            // ja: 許可済み
            return Text("Allowed")
        case .denied:
            // ja: 拒否
            return Text("Denied")
        case .notDetermined:
            // ja: 未確認
            return Text("Not determined")
        @unknown default:
            // ja: 不明
            return Text("Unknown")
        }
    }

    private func notificationAuthorizationText(_ status: UNAuthorizationStatus) -> Text {
        switch status {
        case .authorized, .provisional, .ephemeral:
            // ja: 許可済み
            return Text("Allowed")
        case .denied:
            // ja: 拒否
            return Text("Denied")
        case .notDetermined:
            // ja: 未確認
            return Text("Not determined")
        @unknown default:
            // ja: 不明
            return Text("Unknown")
        }
    }

    private func refreshPermissions() async {
        alarmAuthorization = AlarmKitScheduler.authorizationState
        notificationAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 未確認ならその場で要求し、拒否済みなら OS の設定アプリを開く (再要求はアプリからはできない)
    private func handleAlarmPermissionTap() async {
        switch alarmAuthorization {
        case .notDetermined:
            do {
                alarmAuthorization = try await AlarmKitScheduler.requestAuthorization()
                permissionError = nil
            } catch {
                permissionError = error.localizedDescription
            }
        case .denied:
            openSystemSettings()
        default:
            break
        }
    }

    private func handleNotificationPermissionTap() async {
        switch notificationAuthorization {
        case .notDetermined:
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                permissionError = nil
            } catch {
                permissionError = error.localizedDescription
            }
            UIApplication.shared.registerForRemoteNotifications()
            await refreshPermissions()
        case .denied:
            openSystemSettings()
        default:
            break
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: - プラン

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
