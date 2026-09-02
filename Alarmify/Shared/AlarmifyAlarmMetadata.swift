import AlarmKit

/// AlarmKit のアラームと自アプリのデータを対応付けるメタデータ。
/// AlarmMetadata 準拠型は app 本体と Widget Extension の両ターゲットに所属させる必要がある (Live Activity の描画側でも型を解決するため)
struct AlarmifyAlarmMetadata: AlarmMetadata {
    /// 発火画面・Live Activity に表示するタイトル。外部サービスから送られた文言をそのまま使う
    var title: String?
}
