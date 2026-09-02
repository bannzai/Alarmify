import SwiftUI

/// 動作確認用の設定を切り替える開発者メニュー。DEBUG / TestFlight でのみ導線を出す
struct DeveloperMenuView: View {
    @State private var session = AccountSession.shared
    @State private var settings = DeveloperMenu.settings

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
                Text(settings.backend.alarmsBaseURL.absoluteString)
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
        }
        // ja: 開発者メニュー
        .navigationTitle(Text("Developer menu"))
    }
}

#Preview {
    NavigationStack {
        DeveloperMenuView()
    }
}
