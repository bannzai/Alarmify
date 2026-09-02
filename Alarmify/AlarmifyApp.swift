import SwiftUI

/// Alarmify アプリのエントリポイント
@main
struct AlarmifyApp: App {
    /// APNs のデバイストークン受信と background push の受信は UIApplicationDelegate でしか受け取れないため adaptor で接続する
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        ProEntitlement.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 購入・復元・期限切れによる entitlement の変化をアプリの生存中ずっとキャッシュへ反映し続ける
                    await ProEntitlement.observeCustomerInfo()
                }
        }
    }
}
