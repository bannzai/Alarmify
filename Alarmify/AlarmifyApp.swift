import SwiftUI

/// Alarmify アプリのエントリポイント
@main
struct AlarmifyApp: App {
    /// APNs のデバイストークン受信と background push の受信は UIApplicationDelegate でしか受け取れないため adaptor で接続する
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if isSnapshotUITest {
                // 多言語スクリーンショット撮影では撮影対象 (本番画面の Preview) の一覧を直接表示する。
                // 撮影結果がネットワークや keychain の状態に依存しないよう、匿名認証のサインインも行わない
                SnapshotUITestPage()
            } else {
                contentView
            }
            #else
            contentView
            #endif
        }
    }

    private var contentView: some View {
        ContentView()
            // 匿名認証のアカウントは起動時に自動で作る (ユーザーの操作を挟まない)
            .task { await AccountSession.shared.signIn() }
    }
}
