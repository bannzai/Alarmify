import SwiftUI

/// 動作確認用の設定を切り替える開発者メニュー。DEBUG / TestFlight でのみ導線を出す
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

    private struct PushPayloadResult {
        var message: String
        var isError: Bool
    }

    var body: some View {
        List {
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
        }
        // ja: 開発者メニュー
        .navigationTitle(Text("Developer menu"))
        .sheet(item: $paywallTrigger) { trigger in
            PaywallPage(trigger: trigger)
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

    /// 組み立てた push payload を push 受信時と同じ経路で AlarmKit に反映し、結果を表示する
    private func applyPushPayload(_ userInfo: [AnyHashable: Any]) async {
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
}

#Preview {
    NavigationStack {
        DeveloperMenuView()
    }
}
