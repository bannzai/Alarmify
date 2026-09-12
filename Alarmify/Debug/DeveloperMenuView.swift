import AlarmKit
import SwiftUI

/// 動作確認用の設定を切り替える開発者メニュー。DEBUG / TestFlight でのみ導線を出す。
/// 技術検証用の情報 (権限状態・登録済みアラーム・APNs / FCM トークン・配送先の登録) もホームからここへ移した
struct DeveloperMenuView: View {
    @State private var session = AccountSession.shared
    @State private var settings = DeveloperMenu.settings
    /// 無料枠の上限に達した時のペイウォール。通常操作では API トークン画面で 2 つ目の発行が `plan_limit_exceeded` で
    /// 拒否された時に開くが、上限に達したアカウントを用意せずに表示だけを確認できるようここからも開く
    /// (`.claude/rules/debug-menu-for-verification.md`)
    @State private var paywallTrigger: PaywallTrigger?
    /// 直近の push payload 適用の結果。成否を画面上で確認できるようにする
    @State private var pushPayloadResult: PushPayloadResult?
    /// 進行中の push payload 適用。schedule (AlarmKit の登録完了を待つ) と cancel が重ならないよう、次の適用は前の完了を待ってから始める
    @State private var pushPayloadTask: Task<Void, Never>?
    /// 外観の上書き (RootView が同じキーを購読して即時に反映する)。空はシステムに従う
    @AppStorage(.developerAppearance) private var developerAppearance = ""
    /// オンボーディングの完了フラグ。false に戻すとホームの代わりにオンボーディングが出る
    @AppStorage(.onboardingCompleted) private var onboardingCompleted = false
    /// 表示言語の上書き。反映には再起動が要るため、保存後に案内を出す
    @State private var languageOverride = DeveloperMenu.languageOverride
    @State private var authorizationState = AlarmKitScheduler.authorizationState
    @State private var alarms: [Alarm] = []
    @State private var deviceToken = DeviceTokenStore.load()
    /// 権限の要求・テストアラームの登録・取消に失敗した時のエラー
    @State private var errorMessage: String?

    private struct PushPayloadResult {
        var message: String
        var isError: Bool
    }

    var body: some View {
        List {
            Section {
                Picker(selection: $developerAppearance) {
                    // ja: システム
                    Text("System").tag("")
                    // ja: ライト
                    Text("Light").tag(DeveloperAppearance.light.rawValue)
                    // ja: ダーク
                    Text("Dark").tag(DeveloperAppearance.dark.rawValue)
                } label: {
                    // ja: 外観
                    Text("Appearance")
                }
                // 選択肢をその場に並べ、mobile-mcp / WDA からラベルで直接タップできるようにする (メニュー形式は開く操作が 1 段増える)
                .pickerStyle(.segmented)
                .accessibilityIdentifier("debug_appearance")
                Picker(selection: $languageOverride) {
                    // ja: システム
                    Text("System").tag(DeveloperLanguage?.none)
                    // 言語名。翻訳しない
                    Text(verbatim: "English").tag(DeveloperLanguage?.some(.english))
                    Text(verbatim: "日本語").tag(DeveloperLanguage?.some(.japanese))
                } label: {
                    // ja: 表示言語
                    Text("Language")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("debug_language")
                .onChange(of: languageOverride) { _, newValue in
                    DeveloperMenu.languageOverride = newValue
                }
                Button {
                    onboardingCompleted = false
                } label: {
                    // ja: オンボーディングをもう一度表示する
                    Text("Show onboarding again")
                }
                .accessibilityIdentifier("debug_show_onboarding")
            } header: {
                // ja: 画面の確認
                Text("Screen verification")
            } footer: {
                // ja: 表示言語はアプリを再起動すると反映されます。
                Text("Relaunch the app to apply the language.")
            }

            Section {
                Picker(selection: $settings.backend) {
                    ForEach(AlarmifyBackend.allCases, id: \.self) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                } label: {
                    // ja: 接続先
                    Text("Backend")
                }
                .accessibilityIdentifier("debug_backend")
                // アプリ向け (appApi) と外部サービス向け (alarmsApi) は別の関数のため、両方の接続先を出す
                Text(settings.backend.appBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(settings.backend.alarmsAPIBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } header: {
                // ja: バックエンド
                Text("Backend")
            }

            Section {
                Toggle(isOn: $settings.stubAPIClient) {
                    // ja: 通信をスタブに差し替える
                    Text("Use a stubbed API client")
                }
                .accessibilityIdentifier("debug_stub_api_client")
            } footer: {
                // ja: バックエンドを起動していなくても、API トークンの発行と失効の画面を確認できます。
                Text("Lets you exercise issuing and revoking tokens without a running backend.")
            }

            Section {
                Button {
                    Task { await session.apply(settings: settings) }
                } label: {
                    // ja: 設定を反映する
                    Text("Apply")
                }
                .accessibilityIdentifier("debug_apply")
            } footer: {
                if session.backendChangePendingRestart {
                    // ja: 接続先の変更はアプリを再起動すると反映されます。
                    Text("Restart the app to switch the backend.")
                        .accessibilityIdentifier("debug_pending_restart")
                }
            }

            Section {
                Button {
                    paywallTrigger = .freeQuotaExceeded
                } label: {
                    // ja: 無料枠の上限のペイウォールを表示
                    Text("Show the free quota paywall")
                }
                .accessibilityIdentifier("debug_show_free_quota_paywall")
            } header: {
                // ja: 課金
                Text("Subscription")
            }

            Section {
                Button {
                    enqueuePushPayload(DebugPushPayload.scheduleUserInfo(fireDate: .now.addingTimeInterval(DebugPushPayload.defaultFireInterval)))
                } label: {
                    // ja: schedule の payload を適用する (90 秒後に発火)
                    Text("Apply a schedule payload (fires in 90 seconds)")
                }
                .accessibilityIdentifier("debug_apply_push_schedule")
                Button {
                    enqueuePushPayload(DebugPushPayload.cancelUserInfo())
                } label: {
                    // ja: cancel の payload を適用する
                    Text("Apply a cancel payload")
                }
                .accessibilityIdentifier("debug_apply_push_cancel")
                if let pushPayloadResult {
                    Text(pushPayloadResult.message)
                        .font(.caption)
                        .foregroundStyle(pushPayloadResult.isError ? .red : .secondary)
                        .accessibilityIdentifier("debug_push_payload_result")
                }
            } header: {
                // ja: push payload
                Text("Push payload")
            } footer: {
                // ja: push 受信時と同じ経路 (AlarmRequest → AlarmKitScheduler.apply) で、固定 id のアラームを AlarmKit に登録・取消します。simulator では simctl push がこの経路を通らないため、ここから検証します。
                Text("Runs the same path as a received push (AlarmRequest → AlarmKitScheduler.apply) to schedule or cancel an alarm with a fixed id. Use this on the simulator, where simctl push does not reach that path.")
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
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
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
        }
        // ja: 開発者メニュー
        .navigationTitle(Text("Developer menu"))
        .sheet(item: $paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
        }
        .task {
            refresh()
            // push 受信や開発者メニューの payload 適用で変わった登録済みアラームをその場で反映する
            for await alarms in AlarmKitScheduler.alarmUpdates {
                self.alarms = alarms
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refresh()
        }
    }

    /// push payload の適用を直列化する。前の適用が終わってから次を始め、最後に押した操作の結果が最終状態になるようにする
    private func enqueuePushPayload(_ userInfo: [AnyHashable: Any]) {
        let previous = pushPayloadTask
        pushPayloadTask = Task {
            await previous?.value
            await applyPushPayload(userInfo)
        }
    }

    /// 組み立てた push payload を push 受信時と同じ経路で AlarmKit に反映し、結果を表示する。
    /// 適用結果の報告も push 受信時と同じ経路 (キュー → バックエンド) で送る (固定 id はサーバーに記録が無いため 404 で捨てられる)
    private func applyPushPayload(_ userInfo: [AnyHashable: Any]) async {
        defer { Task { await session.flushAlarmApplyReports() } }
        do {
            let request = try await DebugPushPayload.apply(userInfo: userInfo)
            switch request.action {
            case .schedule:
                let fireDate = request.fireDate.map { $0.formatted(date: .omitted, time: .standard) } ?? "-"
                // ja: %2$@ に %1$@ を登録しました
                pushPayloadResult = PushPayloadResult(message: String(localized: "Scheduled \(request.id.uuidString) at \(fireDate)"), isError: false)
            case .cancel:
                // ja: %@ を取り消しました
                pushPayloadResult = PushPayloadResult(message: String(localized: "Cancelled \(request.id.uuidString)"), isError: false)
            }
        } catch {
            pushPayloadResult = PushPayloadResult(message: error.localizedDescription, isError: true)
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
            try await TestAlarm.schedule()
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

#Preview {
    NavigationStack {
        DeveloperMenuView()
    }
}
