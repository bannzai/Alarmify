import SwiftUI

/// AppStoreScreenshots ターゲットの起動エントリ。
/// 撮影対象 (スクショページの Preview) 一覧を表示し、UITest がボタンをタップして各ページへ遷移する
/// (取り込み元: bannzai/mementomorning の同名ファイル)
@main
struct AppStoreScreenshotsApp: App {
    var body: some Scene {
        WindowGroup {
            AppStoreScreenshotsRootPage()
                // ホームインジケーターを非表示にする。NavigationView の遷移先に付けるだけでは効かず、
                // 6.5 インチ (iPhone 13 Pro Max) で写り込むことを取り込み元で実測したため root に付ける
                .persistentSystemOverlays(.hidden)
        }
    }
}
