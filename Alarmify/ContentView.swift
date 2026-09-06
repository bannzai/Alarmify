import AlarmKit
import SwiftUI

/// ホーム。次に鳴るアラームと直近の履歴を先頭に出し、その下に技術検証用の情報
/// (AlarmKit の権限状態・登録済みアラーム・APNs デバイストークン) をまとめる。見た目は仮 UI で、受領デザインの反映は #6 で行う
struct ContentView: View {
    @State private var session = AccountSession.shared
    @State private var authorizationState = AlarmKitScheduler.authorizationState
    @State private var alarms: [Alarm] = []
    @State private var deviceToken = DeviceTokenStore.load()
    @State private var errorMessage: String?
    /// バックエンドの履歴 (新しい順)。件数の上限はサーバーがプランで決める
    @State private var history: [AlarmHistoryEntry] = []
    /// 履歴の取得に失敗したエラーの説明。成功したら nil
    @State private var historyError: String?
    /// 履歴を読み込み中かどうか。初回の空表示と「履歴なし」を区別する
    @State private var historyLoading = false
    /// 表示中のペイウォールの文脈。履歴の続きを見る導線から開く
    @State private var paywallTrigger: PaywallTrigger?

    /// 履歴の取得件数。無料プランはサーバー側で直近数件に切り詰められ、Pro はこの件数まで返る (ホームに収まる量)
    private static let historyLimit = 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 発火時刻を過ぎたアラームを (再読み込みを待たずに) その場でカードから外すため、
                    // 残り時間の表示と同じ 1 秒周期で「次に鳴るアラーム」を判定し直す
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let nextAlarm = nextAlarm(now: context.date), let fireDate = nextAlarm.fixedFireDate {
                            VStack(alignment: .leading, spacing: 4) {
                                if let title = AlarmTitleStore.shared.title(id: nextAlarm.id) {
                                    // 外部サービスから送られたタイトルはそのまま表示する
                                    Text(verbatim: title)
                                        .font(.headline)
                                }
                                Text(fireDate, format: .dateTime.month().day().hour().minute())
                                    .font(.title2.monospacedDigit())
                                Text(fireDate, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("home_next_alarm")
                        } else {
                            // ja: 次に鳴るアラームはありません
                            Text("No upcoming alarm")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("home_next_alarm_empty")
                        }
                    }
                } header: {
                    // ja: 次に鳴るアラーム
                    Text("Next alarm")
                }

                Section {
                    if historyLoading && history.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let historyError {
                        Text(historyError)
                            .foregroundStyle(.red)
                    } else if session.uid == nil {
                        // 履歴はサインイン後にしか取れない。サインイン中に「履歴なし」と見せない
                        // ja: サインイン中
                        Text("Signing in")
                            .foregroundStyle(.secondary)
                    } else if history.isEmpty {
                        // ja: 履歴はまだありません
                        Text("No alarms yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(history) { entry in
                        historyRow(entry)
                    }
                    if !ProEntitlement.isPro {
                        Button {
                            paywallTrigger = .alarmHistory
                        } label: {
                            // ja: Pro でもっと履歴を見る
                            Text("See more history with Pro")
                        }
                        .accessibilityIdentifier("home_history_upgrade")
                    }
                } header: {
                    // ja: 直近の履歴
                    Text("Recent alarms")
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
                        // ja: アカウント
                        Text("Account")
                    }
                    LabeledContent {
                        deviceRegistrationText
                    } label: {
                        // ja: 配送先の登録
                        Text("Device registration")
                    }
                    Button {
                        Task { await session.retryDeviceRegistration() }
                    } label: {
                        // ja: 配送先を登録し直す
                        Text("Register this device again")
                    }
                    NavigationLink {
                        APITokenView()
                    } label: {
                        // ja: API トークン
                        Text("API tokens")
                    }
                    .accessibilityIdentifier("account_api_tokens")
                    if DeveloperMenu.isAvailable {
                        NavigationLink {
                            DeveloperMenuView()
                        } label: {
                            // ja: 開発者メニュー
                            Text("Developer menu")
                        }
                        .accessibilityIdentifier("debug_menu")
                    }
                    if let signInError = session.signInError {
                        Text(signInError)
                            .foregroundStyle(.red)
                    }
                } header: {
                    // ja: アカウント
                    Text("Account")
                }

                Section {
                    LabeledContent {
                        authorizationStateText
                    } label: {
                        // ja: 権限
                        Text("Permission")
                    }
                    Button {
                        Task { await requestAuthorization() }
                    } label: {
                        // ja: アラームの権限を許可する
                        Text("Allow alarms")
                    }
                    Button {
                        Task { await scheduleTestAlarm() }
                    } label: {
                        // ja: 1 分後にテストアラームを登録する
                        Text("Schedule a test alarm in 1 minute")
                    }
                } header: {
                    Text("AlarmKit")
                }

                Section {
                    if alarms.isEmpty {
                        // ja: 登録済みのアラームはありません
                        Text("No alarms scheduled")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(alarms, id: \.id) { alarm in
                        VStack(alignment: .leading, spacing: 4) {
                            if case .fixed(let fireDate)? = alarm.schedule {
                                Text(fireDate, format: .dateTime.month().day().hour().minute())
                            }
                            Text(alarm.id.uuidString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                cancel(alarm)
                            } label: {
                                // ja: アラームを取り消す
                                Text("Cancel alarm")
                            }
                        }
                    }
                } header: {
                    // ja: 登録済みのアラーム
                    Text("Scheduled alarms")
                }

                Section {
                    if let deviceToken {
                        Text(deviceToken)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        // ja: 未登録 (実機でのみ取得できます)
                        Text("Not registered (available on a physical device only)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    // ja: APNs デバイストークン
                    Text("APNs device token")
                }

                Section {
                    if let fcmRegistrationToken = session.fcmRegistrationToken ?? DeviceTokenStore.loadFCMRegistrationToken() {
                        Text(fcmRegistrationToken)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else {
                        // ja: 未取得
                        Text("Not available yet")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    // ja: FCM 登録トークン
                    Text("FCM registration token")
                }

                Section {
                    NavigationLink {
                        // 発行済みトークンの平文は発行直後の API トークン画面にしか無いため、ここからはプレースホルダ入りで表示する
                        RecipesView(apiToken: nil, backend: session.settings.backend)
                    } label: {
                        // ja: 連携レシピ
                        Label("Integration recipes", systemImage: "link")
                    }
                    .accessibilityIdentifier("open_recipes")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } header: {
                        // ja: エラー
                        Text("Error")
                    }
                }
            }
            .navigationTitle("Signalarm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        // ja: 設定
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("open_settings")
                }
            }
            .refreshable {
                refresh()
                await loadHistory()
            }
            // 起動直後はサインインの完了前に走って履歴を取れないため、uid が決まったらもう一度読む
            .task(id: session.uid) {
                refresh()
                await loadHistory()
            }
            .task {
                // push (Notification Service Extension / background push) や開発者メニューで登録・取消されたアラームと、発火による状態の変化を
                // 再読み込みを待たずに反映する。前面中に Extension が登録した時は、この app 本体しか報告を送れず前面復帰も起きないため、
                // ここで Extension が積んだ報告を送り、サーバー側に増えた履歴も読み直す
                for await alarms in AlarmKitScheduler.alarmUpdates {
                    self.alarms = alarms
                    await session.flushAlarmApplyReports()
                    await loadHistory()
                }
            }
            .onChange(of: session.alarmApplyReportsFlushedAt) {
                // この端末の反映結果がサーバーに届いたので、履歴の状態表示を読み直す
                Task { await loadHistory() }
            }
            .sheet(item: $paywallTrigger, onDismiss: {
                // Pro を購入・復元して閉じた時に、無料プランの 3 件のままの履歴を読み直す (サーバーのプランは RevenueCat の webhook で変わるため、
                // 反映が遅れていればこの読み直しではまだ 3 件で、次の再読み込みで増える)
                Task { await loadHistory() }
            }) { trigger in
                PaywallPage(trigger: trigger)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refresh()
                // 起動時のサインインが一過性のエラーで失敗していた場合、前面復帰のたびにやり直す。
                // サインインの中で未送信の適用結果も送られるため、その後に履歴を読み直す
                Task {
                    await session.signIn()
                    await loadHistory()
                }
            }
        }
    }

    /// 次に鳴るアラーム。この端末に登録済みの固定日時のアラームのうち、発火時刻が `now` より後の最も早いもの
    private func nextAlarm(now: Date) -> Alarm? {
        alarms
            .filter { ($0.fixedFireDate ?? .distantPast) > now }
            .min { ($0.fixedFireDate ?? .distantFuture) < ($1.fixedFireDate ?? .distantFuture) }
    }

    private func historyRow(_ entry: AlarmHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = entry.title {
                // 外部サービスから送られたタイトルはそのまま表示する
                Text(verbatim: title)
                    .font(.headline)
            } else {
                // ja: タイトルなし
                Text("Untitled alarm")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text(entry.fireAt, format: .dateTime.month().day().hour().minute())
            // 発火時刻を迎えた瞬間に「登録済み」から「鳴りました」へ切り替えるため、次に鳴るアラームのカードと同じ 1 秒周期で判定し直す。
            // `.explicit([entry.fireAt])` は最初の描画から context.date が発火時刻になり、未来の登録が「鳴りました」と出る (simtunnel で確認) ため使わない
            TimelineView(.periodic(from: .now, by: 1)) { context in
                historyStatusText(entry, now: context.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("home_history_\(entry.id)")
    }

    /// 履歴 1 件の状態。サーバーの状態と、この端末からの反映結果・配送結果を組み合わせて決める。
    /// 発火したかどうかはサーバーにも端末にも記録が無い (AlarmKit は発火を通知しない) ため、発火時刻の経過で表す
    private func historyStatusText(_ entry: AlarmHistoryEntry, now: Date) -> Text {
        switch entry.status {
        case .canceled:
            let report = entry.deviceReport(deviceID: DeviceIdentifier.current)
            if let report, report.action == .cancel, report.result == .failed {
                // この iPhone にはアラームが残っていて鳴り得るので、取り消し済みと言い切らない
                // ja: この iPhone で取り消しに失敗: %@
                return Text("Failed to cancel on this iPhone: \(report.error ?? "")")
            }
            if let report, report.action == .cancel {
                // ja: 取り消し済み
                return Text("Canceled")
            }
            if let delivery = entry.delivery, delivery.failureCount > 0 {
                // 配送結果は端末ごとではなく全端末の合計のため、他の端末には届いていても、報告の無いこの端末に届いていない可能性がある間は取り消し済みと言い切らない
                // ja: 取り消しの push がこの iPhone に届いていない可能性があります
                return Text("Cancel push may not have reached this iPhone")
            }
            if let report, report.action == .schedule, report.result == .applied {
                // この iPhone に登録済みのまま、取り消しの指示がまだ反映されていない
                // ja: 取り消し済み (この iPhone への反映を待っています)
                return Text("Canceled, waiting for this iPhone")
            }
            // ja: 取り消し済み
            return Text("Canceled")
        case .scheduled:
            if let report = entry.deviceReport(deviceID: DeviceIdentifier.current) {
                switch (report.action, report.result) {
                case (.schedule, .applied) where entry.fireAt <= now:
                    // ja: 鳴りました
                    return Text("Rang")
                case (.schedule, .applied):
                    // ja: この iPhone に登録済み
                    return Text("Scheduled on this iPhone")
                case (.schedule, .failed):
                    // ja: この iPhone で登録に失敗: %@
                    return Text("Failed on this iPhone: \(report.error ?? "")")
                case (.cancel, _):
                    // サーバーでは登録し直されているが、この端末はまだ取り消しまでしか反映していない
                    // ja: この iPhone への反映を待っています
                    return Text("Waiting for this iPhone")
                }
            }
            if let delivery = entry.delivery, delivery.failureCount > 0, delivery.successCount == 0 {
                // ja: push を配送できませんでした
                return Text("Push could not be delivered")
            }
            if entry.fireAt <= now {
                // ja: 発火時刻を過ぎました
                return Text("Alarm time has passed")
            }
            // ja: この iPhone への反映を待っています
            return Text("Waiting for this iPhone")
        }
    }

    /// バックエンドの履歴を読み直す。失敗はエラーとして表示し、前回の内容は残さない (古い履歴を最新として見せない)。
    /// 未サインインは起動直後に通る正常な経路のためエラーにせず、サインイン後の読み直しに任せる
    private func loadHistory() async {
        #if DEBUG
        // 多言語スクリーンショット撮影はサインインしないが、keychain に残った匿名アカウントで本番の履歴を読んでしまうと
        // 撮影結果がネットワークと keychain の状態に依存する (AlarmifyApp の方針) ため、履歴は読まず空のまま撮る
        if isSnapshotUITest { return }
        #endif
        historyLoading = true
        defer { historyLoading = false }
        do {
            let loaded = try await session.client.alarmHistory(limit: Self.historyLimit)
            guard !Task.isCancelled else { return }
            history = loaded
            historyError = nil
        } catch AlarmifyAPIError.notSignedIn {
            history = []
            historyError = nil
        } catch {
            // サインインの完了で `.task(id:)` が読み直す時、進行中の取得は取り消される。取り消しはエラーではなく、後続の取得結果に任せる
            guard !Task.isCancelled else { return }
            history = []
            historyError = error.localizedDescription
        }
    }

    private var deviceRegistrationText: Text {
        switch session.deviceRegistration {
        case .notRegistered:
            // ja: 未登録
            return Text("Not registered")
        case .registering:
            // ja: 登録中
            return Text("Registering")
        case .registered:
            // ja: 登録済み
            return Text("Registered")
        case .failed(let message):
            return Text(message)
        }
    }

    private var authorizationStateText: Text {
        switch authorizationState {
        case .authorized:
            // ja: 許可済み
            return Text("Authorized")
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

    private func refresh() {
        authorizationState = AlarmKitScheduler.authorizationState
        alarms = AlarmKitScheduler.alarms
        deviceToken = DeviceTokenStore.load()
    }

    private func requestAuthorization() async {
        do {
            authorizationState = try await AlarmKitScheduler.requestAuthorization()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleTestAlarm() async {
        do {
            // ja: テストアラーム
            try await AlarmKitScheduler.schedule(id: UUID(), fireDate: .now.addingTimeInterval(60), title: String(localized: "Test alarm"))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func cancel(_ alarm: Alarm) {
        do {
            try AlarmKitScheduler.cancel(id: alarm.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

/// ContentView の Preview。多言語スクリーンショット撮影 (AlarmifySnapshotUITests) が
/// SnapshotUITestPage 経由で参照するため、#Preview マクロではなく型名を持つ PreviewProvider で定義する
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
