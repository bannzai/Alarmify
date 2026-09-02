import os

extension Logger {
    private static let subsystem = "com.bannzai.Alarmify"

    /// push の受信・APNs 登録・AlarmKit への反映に関するログ。app 本体と Notification Service Extension で共通
    static let push = Logger(subsystem: subsystem, category: "push")

    /// アカウントの認証情報の保存・削除に関するログ
    static let account = Logger(subsystem: subsystem, category: "account")
}
