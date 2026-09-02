import Foundation

/// 多言語スクリーンショット撮影 (AlarmifySnapshotUITests) の実行中かどうか。
/// UITest が起動引数 isSnapshotUITest を渡し、AlarmifyApp が撮影用の起動画面へ分岐する
var isSnapshotUITest: Bool { ProcessInfo.processInfo.arguments.contains("isSnapshotUITest") }
