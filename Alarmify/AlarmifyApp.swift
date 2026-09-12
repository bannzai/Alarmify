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
                rootView
            }
            #else
            rootView
            #endif
        }
    }

    /// サインインと課金状態の監視は、オンボーディングとホームのどちらが出ていても続ける
    /// (オンボーディングの最初のトークン発行にはサインインが要る)
    private var rootView: some View {
        RootView()
            // 匿名認証のアカウントは起動時に自動で作る (ユーザーの操作を挟まない)
            .task { await AccountSession.shared.signIn() }
            .task {
                // 購入・復元・期限切れによる entitlement の変化をアプリの生存中ずっとキャッシュへ反映し続ける
                await ProEntitlement.observeCustomerInfo()
            }
    }
}

/// オンボーディングの完了前はオンボーディング、完了後はホームを表示する。
/// 開発者メニューの外観の上書き (ダーク / ライトの動作確認用) もここで適用する
struct RootView: View {
    @AppStorage(.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(.developerAppearance) private var developerAppearance = ""

    var body: some View {
        Group {
            if onboardingCompleted {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(overriddenColorScheme)
    }

    /// 開発者メニューで選んだ外観。解放されていない配布 (App Store) では常にシステムに従う
    private var overriddenColorScheme: ColorScheme? {
        guard DeveloperMenu.isAvailable else { return nil }
        switch DeveloperAppearance(rawValue: developerAppearance) {
        case .light: return .light
        case .dark: return .dark
        case nil: return nil
        }
    }
}
