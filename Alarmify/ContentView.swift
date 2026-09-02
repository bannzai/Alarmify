import AlarmKit
import SwiftUI

/// 技術検証用のトップ画面。AlarmKit の権限状態・登録済みアラーム・APNs デバイストークンを表示し、
/// 手元でのアラーム登録と push 経路の検証に必要な情報をまとめる
struct ContentView: View {
    @State private var session = AccountSession.shared
    @State private var authorizationState = AlarmKitScheduler.authorizationState
    @State private var alarms: [Alarm] = []
    @State private var deviceToken = DeviceTokenStore.load()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
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
                                // ja: 取り消す
                                Text("Cancel")
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
            .navigationTitle("Alarmify")
            .refreshable { refresh() }
            .task { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                refresh()
                // 起動時のサインインが一過性のエラーで失敗していた場合、前面復帰のたびにやり直す
                Task { await session.signIn() }
            }
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

#Preview {
    ContentView()
}
