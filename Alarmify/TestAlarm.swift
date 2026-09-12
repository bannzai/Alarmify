import Foundation

/// アプリ内から鳴らすテストアラーム。ホームの「Ring a test」とオンボーディングの最後の画面が同じ登録を行う
enum TestAlarm {
    /// 発火までの秒数。「1 分後」と案内する文言 (ホーム・オンボーディング) と揃える
    static let fireInterval: TimeInterval = 60

    /// テストアラームを登録し、発火日時を返す
    @discardableResult
    static func schedule() async throws -> Date {
        let fireDate = Date.now.addingTimeInterval(fireInterval)
        // ja: テストアラーム
        try await AlarmKitScheduler.schedule(id: UUID(), fireDate: fireDate, title: String(localized: "Test alarm"))
        return fireDate
    }
}
