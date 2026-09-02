import SwiftUI

/// Alarmify アプリのエントリポイント
@main
struct AlarmifyApp: App {
    /// APNs のデバイストークン受信と background push の受信は UIApplicationDelegate でしか受け取れないため adaptor で接続する
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
