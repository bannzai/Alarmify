import XCTest

extension XCUIApplication {
    /// 多言語スクリーンショット撮影用に XCUIApplication を生成する。
    /// isSnapshotUITest で AlarmifyApp を SnapshotUITestPage へ分岐させる (Alarmify/Utils/Environments.swift のフラグ名に合わせる)
    static func instantiate() -> Self {
        let app = self.init()
        app.launchArguments += ["isSnapshotUITest"]
        return app
    }
}
