import XCTest

extension XCUIApplication {
    /// テスト用に XCUIApplication を生成する。
    /// AppStoreScreenshots アプリは起動引数による分岐を持たないが、
    /// 各テストファイルの生成手順を AlarmifySnapshotUITests と揃えるため同名のファクトリを用意する
    static func instantiate() -> Self {
        self.init()
    }
}
