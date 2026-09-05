import os

extension Logger {
    private static let subsystem = "com.bannzai.Alarmify"

    /// push の受信・APNs 登録・AlarmKit への反映に関するログ。app 本体と Notification Service Extension で共通
    static let push = Logger(subsystem: subsystem, category: "push")

    /// App Check のトークン取得に関するログ。取得できなくてもリクエストは送るため、失敗はここにだけ残る
    static let appCheck = Logger(subsystem: subsystem, category: "appCheck")

    /// RevenueCat の identity 連携 (logIn) と entitlement の反映に関するログ
    static let purchase = Logger(subsystem: subsystem, category: "purchase")
}
