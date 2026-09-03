import SwiftUI

/// Alarmify アプリのエントリポイント
@main
struct AlarmifyApp: App {
    /// APNs のデバイストークン受信と background push の受信は UIApplicationDelegate でしか受け取れないため adaptor で接続する
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if DEBUG
        if isSnapshotUITest {
            // 撮影対象の本番画面 (ContentView) は App Group に残ったトークンと登録済みアラームを表示するため、
            // 以前の実行の状態に依存せず、トークンや UUID が画像 (翻訳チェックの Issue に添付される) に写らないよう空にする。
            // RevenueCat も configure しない (API キーの有無や通信状況で表示が変わらないようにする)
            DeviceTokenStore.removeAll()
            for alarm in AlarmKitScheduler.alarms {
                try? AlarmKitScheduler.cancel(id: alarm.id)
            }
            return
        }
        #endif
        ProEntitlement.configureIfPossible()
    }

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
            .task {
                // 購入・復元・期限切れによる entitlement の変化をアプリの生存中ずっとキャッシュへ反映し続ける
                await ProEntitlement.observeCustomerInfo()
            }
    }
}
