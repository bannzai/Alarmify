import Foundation

/// App Group を共有する app 本体と Notification Service Extension の間で、共有ストア (App Group の UserDefaults) の
/// 「読み取り → 変更 → 書き戻し」を 1 つずつ実行するための排他ロック。
/// UserDefaults は個々の読み書きはプロセスをまたいでも安全だが、この並びをひとまとまりとしては守らないため、
/// 2 つのプロセス (または同じプロセスの 2 つのタスク) が同時に書き換えると後から書いた側が相手の変更を消す。
/// App Group コンテナ内のロックファイルに flock(2) の排他ロックをかけて直列化する (flock はプロセスをまたいで効き、
/// 同じプロセス内でも open し直した記述子どうしは互いに待つ)
struct SharedStoreLock: Sendable {
    /// ロックファイルの場所。nil ならロックせずに実行する (ユニットテストの単独実行など、競合する相手がいない場合)
    let fileURL: URL?

    /// App Group コンテナのロック。コンテナが解決できない構成 (entitlements 不足) ではロックなしで動かす
    /// (ロックが無くても単体の読み書きは成立するため、`AppGroup.userDefaults` のように落とさない)
    static let appGroup = SharedStoreLock(
        fileURL: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appending(path: "shared-store.lock")
    )

    /// body をロックの中で実行する。ロックファイルを開けない・ロックできない場合はロックなしで実行する
    /// (書き込みを止めるより、まれな競合で 1 件を失う方を選ぶ)。同じロックの中で再びこの関数を呼ぶと自分を待ち続けるため、入れ子にしない
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        guard let fileURL else { return try body() }
        let descriptor = open(fileURL.path(percentEncoded: false), O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return try body() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return try body() }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
