import Foundation

/// この端末で AlarmKit に登録したアラームの表示タイトル (id ごと)。
/// AlarmKit の `Alarm` からは登録時の attributes (タイトル) を読み戻せないため、ホームの「次に鳴るアラーム」に出す文言をここに持つ。
/// App Group に置き、Notification Service Extension からの登録も同じ場所に書く。書き換えは `lock` の中で行い、app 本体と Extension が重なっても互いの変更を消さない
struct AlarmTitleStore {
    private static let key = "alarmTitles"

    let userDefaults: UserDefaults
    let lock: SharedStoreLock

    static let shared = AlarmTitleStore(userDefaults: AppGroup.userDefaults, lock: .appGroup)

    func title(id: UUID) -> String? {
        titles[id.uuidString]
    }

    func save(title: String, id: UUID) {
        lock.withLock {
            var titles = titles
            titles[id.uuidString] = title
            userDefaults.set(titles, forKey: Self.key)
        }
    }

    func remove(id: UUID) {
        lock.withLock {
            var titles = titles
            titles.removeValue(forKey: id.uuidString)
            userDefaults.set(titles, forKey: Self.key)
        }
    }

    private var titles: [String: String] {
        userDefaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
